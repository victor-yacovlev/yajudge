import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'grader_extra_configs.dart';
import 'chrooted_runner.dart';
import 'simple_runner.dart';
import 'submission_processor.dart';
import 'package:path/path.dart' as path;

import 'abstract_runner.dart';

const ReconnectTimeout = Duration(seconds: 5);

class TokenAuthGrpcInterceptor implements ClientInterceptor {
  final String _token;

  TokenAuthGrpcInterceptor(this._token) : super();

  @override
  ResponseStream<R> interceptStreaming<Q, R>(
      ClientMethod<Q, R> method,
      Stream<Q> requests,
      CallOptions options,
      ClientStreamingInvoker<Q, R> invoker) {
    final newOptions = getNewOptions(options);
    return invoker(method, requests, newOptions);
  }

  @override
  ResponseFuture<R> interceptUnary<Q, R>(ClientMethod<Q, R> method, Q request,
      CallOptions options, ClientUnaryInvoker<Q, R> invoker) {
    final newOptions = getNewOptions(options);
    return invoker(method, request, newOptions);
  }

  CallOptions getNewOptions(CallOptions options) {
    return options.mergedWith(CallOptions(metadata: {
      'token': _token,
    }));
  }
}

class GraderService {
  final Logger log = Logger('GraderService');

  final RpcProperties rpcProperties;
  final GraderLocationProperties locationProperties;
  final GraderIdentityProperties identityProperties;
  final GradingLimits defaultLimits;
  final SecurityContext defaultSecurityContext;
  final CompilersConfig compilersConfig;

  late final ClientChannel masterServer;
  late final CourseManagementClient coursesService;
  late final SubmissionManagementClient submissionsService;
  late final GraderProperties _graderProperties;

  GraderService({
    required this.rpcProperties,
    required this.locationProperties,
    required this.identityProperties,
    required this.defaultLimits,
    required this.defaultSecurityContext,
    required this.compilersConfig,
  }) {
    _graderProperties = GraderProperties(
      name: identityProperties.name,
      platform: GradingPlatform(arch: identityProperties.arch),
    );
    masterServer = GrpcOrGrpcWebClientChannel.grpc(
      rpcProperties.host,
      port: rpcProperties.port,
      options: ChannelOptions(
        credentials: const ChannelCredentials.insecure(),
      ),
    );
    final interceptor = TokenAuthGrpcInterceptor(rpcProperties.privateToken);
    coursesService =
        CourseManagementClient(masterServer, interceptors: [interceptor]);
    submissionsService =
        SubmissionManagementClient(masterServer, interceptors: [interceptor]);
    io.ProcessSignal.sigterm.watch().listen((_) => shutdown('SIGTERM'));
    io.ProcessSignal.sigint.watch().listen((_) => shutdown('SIGINT'));
  }

  void handleGraderError(Object? error) {
    Level logLevel = Level.SEVERE;
    bool waitBeforeRestart = false;
    if (error is GrpcError) {
      if (error.code == StatusCode.unauthenticated) {
        logLevel = Level.SHOUT;
      }
      if (error.code == StatusCode.unavailable) {
        waitBeforeRestart = true;
      }
    }
    log.log(logLevel, '$error');
    if (logLevel == Level.SHOUT) {
      io.exit(5);
    }
    if (waitBeforeRestart) {
      Future.delayed(ReconnectTimeout).then((_) => serveSupervised());
    } else {
      serveSupervised();
    }
  }

  void serveSupervised() {
    runZonedGuarded(() async {
      await serveIncomingSubmissions();
    }, (e, s) => handleGraderError(e))!
        .then((_) => serveSupervised());
  }

  Future<void> serveIncomingSubmissions() async {
    while (true) {
      Submission submission = await submissionsService.takeSubmissionToGrade(
          _graderProperties);
      if (submission.id.toInt() > 0) {
        submission = await processSubmission(submission);
        submission = submission.copyWith((s) {
          s.graderName = _graderProperties.name;
        });
        await submissionsService.updateGraderOutput(submission);
      }
      else {
        // no new submissions -- wait and retry
        io.sleep(Duration(seconds: 2));
      }
    }
  }

  Future<Submission> processSubmission(Submission submission) async {
    final courseId = submission.course.dataId;
    final problemId = submission.problemId;
    await loadProblemData(courseId, problemId);
    log.info('processing submission ${submission.id} $courseId/$problemId');
    AbstractRunner runner;
    if (io.Platform.isLinux)
      runner = ChrootedRunner(
        locationProperties: locationProperties,
        courseId: courseId,
        problemId: problemId,
      );
    else
      runner = SimpleRunner(locationProperties: locationProperties);
    SubmissionProcessor processor = SubmissionProcessor(
      submission: submission,
      runner: runner,
      locationProperties: locationProperties,
      defaultLimits: defaultLimits,
      defaultSecurityContext: defaultSecurityContext,
      compilersConfig: compilersConfig,
    );
    await processor.processSubmission();
    Submission result = processor.submission;
    log.info(
        'done processing submission ${submission.id} with status ${result.status
            .name}');
    return result;
  }

  Future<void> loadProblemData(String courseId, String problemId) async {
    String root = locationProperties.coursesCacheDir;
    final problemDir = io.Directory(path.absolute(root, courseId, problemId));
    final problemTimeStampFile = io.File(problemDir.path + '/.timestamp');
    int timeStamp = 0;
    if (problemTimeStampFile.existsSync()) {
      String timeStampData = problemTimeStampFile.readAsStringSync().trim();
      timeStamp = int.parse(timeStampData);
    }
    final request = ProblemContentRequest(
      courseDataId: courseId,
      problemId: problemId,
      cachedTimestamp: Int64(timeStamp),
    );
    final response = await coursesService.getProblemFullContent(request);
    if (response.status == ContentStatus.HAS_DATA) {
      problemDir.createSync(recursive: true);
      String buildDir = problemDir.path + '/build';
      String testsDir = problemDir.path + '/tests';
      io.Directory(buildDir).createSync(recursive: true);
      io.Directory(testsDir).createSync(recursive: true);
      final problemData = response.data;
      final opts = problemData.gradingOptions;
      String compileOptions = opts.extraCompileOptions.join(' ');
      String linkOptions = opts.extraLinkOptions.join(' ');
      io.File(buildDir + '/.compile_options').writeAsStringSync(compileOptions);
      io.File(buildDir + '/.link_options').writeAsStringSync(linkOptions);
      final codeStyles = opts.codeStyles;
      for (final codeStyle in codeStyles) {
        String fileName = codeStyle.styleFile.name;
        String suffix = codeStyle.sourceFileSuffix;
        if (suffix.startsWith('.'))
          suffix = suffix.substring(1);
        io.File(buildDir + '/' + fileName).writeAsBytesSync(
            codeStyle.styleFile.data);
        io.File(buildDir + '/.style_$suffix').writeAsStringSync(
            codeStyle.styleFile.name);
      }
      for (final file in opts.extraBuildFiles.files) {
        io.File(buildDir + '/' + file.name).writeAsBytesSync(file.data);
      }
      final customChecker = opts.customChecker;
      if (customChecker.name.isNotEmpty) {
        io.File(buildDir + '/' + customChecker.name).writeAsBytesSync(
            customChecker.data);
        io.File(buildDir + '/.checker').writeAsStringSync(customChecker.name);
      } else {
        String checkerName = opts.standardChecker;
        String checkerOpts = opts.standardCheckerOpts;
        io.File(buildDir + '/.checker').writeAsStringSync(
            '=$checkerName\n$checkerOpts\n');
      }
      final testsGenerator = opts.testsGenerator;
      if (testsGenerator.name.isNotEmpty) {
        io.File(buildDir + '/' + testsGenerator.name).writeAsBytesSync(
            testsGenerator.data);
        io.File(buildDir + '/.tests_generator').writeAsStringSync(
            testsGenerator.name);
      }

      if (opts.disableValgrind)
        io.File(buildDir + '/.disable_valgrind').createSync(recursive: true);

      final List<String> disabledSanitizers = opts.disableSanitizers;
      if (disabledSanitizers.isNotEmpty) {
        io.File(buildDir + '/.disable_sanitizers').writeAsStringSync(
            disabledSanitizers.join(' '));
      }

      GradingLimits limits = opts.limits;
      String limitsYaml = limitsToYamlString(limits);
      if (limitsYaml
          .trim()
          .isNotEmpty) {
        io.File(buildDir + '/.limits').writeAsStringSync(limitsYaml);
      }

      SecurityContext problemSecurityContext = opts.securityContext;
      String securityContextYaml = securityContextToYamlString(
          problemSecurityContext);
      if (securityContextYaml
          .trim()
          .isNotEmpty) {
        io.File(buildDir + '/.security_context').writeAsStringSync(
            securityContextYaml);
      }
      SecurityContext securityContext = mergeSecurityContext(
          defaultSecurityContext, problemSecurityContext);
      if (io.Platform.isLinux) {
        await buildSecurityContextObjects(
            securityContext, buildDir, courseId, problemId);
      }

      final gzip = io.gzip;
      int testNumber = 1;
      int testsCount = 0;
      for (final testCase in opts.testCases) {
        final stdin = testCase.stdinData;
        final stdout = testCase.stdoutReference;
        final stderr = testCase.stderrReference;
        final bundle = testCase.directoryBundle;
        final args = testCase.commandLineArguments;
        if (stdin.name.isNotEmpty) {
          io.File(testsDir + '/' + stdin.name).writeAsBytesSync(
              gzip.decode(stdin.data));
        }
        if (stdout.name.isNotEmpty) {
          io.File(testsDir + '/' + stdout.name).writeAsBytesSync(
              gzip.decode(stdout.data));
        }
        if (stderr.name.isNotEmpty) {
          io.File(testsDir + '/' + stderr.name).writeAsBytesSync(
              gzip.decode(stderr.data));
        }
        if (bundle.name.isNotEmpty) {
          io.File(testsDir + '/' + bundle.name).writeAsBytesSync(bundle.data);
        }
        if (args.isNotEmpty) {
          String testBaseName = '$testNumber';
          if (testNumber < 10)
            testBaseName = '0' + testBaseName;
          if (testNumber < 100)
            testBaseName = '0' + testBaseName;
          io.File(testsDir + '/' + testBaseName + '.args').writeAsStringSync(
              args);
        }
        testNumber ++;
        testsCount ++;
      }
      io.File(testsDir + "/.tests_count").writeAsStringSync('$testsCount\n');
      problemTimeStampFile.writeAsStringSync(
          '${response.lastModified.toInt()}\n');
    }
  }

  void shutdown(String reason, [bool error = false]) async {
    masterServer.shutdown().timeout(Duration(seconds: 2), onTimeout: () {
      log.info('grader shutdown due to $reason');
      io.exit(error ? 1 : 0);
    });
  }

  Future<void> buildSecurityContextObjects(SecurityContext securityContext,
      String buildDir, String courseId, String problemId) async {
    String binDir = path.dirname(io.Platform.script.path);
    String procLimiterSourcePath = path.normalize(
        path.absolute(binDir, '../src/', 'proc-limiter.c'));
    String tempSourcePath = buildDir + '/.forbidden-functions-wrapper.c';

    final runner = ChrootedRunner(
        locationProperties: locationProperties,
        courseId: courseId,
        problemId: problemId
    );
    final compiler = compilersConfig.cCompiler;
    final options = ['-c', '-fPIC'];
    runner.createDirectoryForSubmission(Submission());
    
    bool allowFork = !securityContext.forbiddenFunctions.contains('fork');
    if (allowFork) {
      io.File(procLimiterSourcePath).copySync(buildDir + '/.proc-limiter.c');
      final arguments = compilersConfig.cBaseOptions + options + [
        '-o', '.proc-limiter.o',
        '.proc-limiter.c'
      ];
      final process = await runner.start(
        0,
        [compiler] + arguments,
        workingDirectory: '/build',
      );
      List<int> stdout = [];
      List<int> stderr = [];
      await process.stdout.listen((chunk) => stdout.addAll(chunk)).asFuture();
      await process.stderr.listen((chunk) => stderr.addAll(chunk)).asFuture();
      int status = await process.exitCode;
      if (status != 0) {
        String errorMessage = utf8.decode(stdout) + '\n' + utf8.decode(stderr);
        log.severe(
            'cant build proc limiter object: $compiler ${arguments.join(
                ' ')}:\n$errorMessage\n');
      }
    }
    if (securityContext.forbiddenFunctions.isNotEmpty) {
      String sourceHeader = r'''
#include <stdio.h>
#include <signal.h>
#include <unistd.h>

static void forbid(const char *name) {
    fprintf(stderr, "yajudge_error: Function '%s' is forbidden\n", name);
    _exit(127);
}
    '''.trimLeft();
      String forbidSource = sourceHeader + '\n';
      for (final name in securityContext.forbiddenFunctions) {
        final line = 'void __wrap_$name() { forbid("$name"); }\n';
        forbidSource += line;
      }
      io.File(tempSourcePath).writeAsStringSync(forbidSource);
      final arguments = compilersConfig.cBaseOptions + options + [
        '-o', '.forbidden-functions-wrapper.o',
        '.forbidden-functions-wrapper.c'
      ];
      final process = await runner.start(
        0,
        [compiler] + arguments,
        workingDirectory: '/build',
      );
      List<int> stdout = [];
      List<int> stderr = [];
      await process.stdout.listen((chunk) => stdout.addAll(chunk)).asFuture();
      await process.stderr.listen((chunk) => stderr.addAll(chunk)).asFuture();
      int status = await process.exitCode;
      if (status != 0) {
        String errorMessage = utf8.decode(stdout) + '\n' + utf8.decode(stderr);
        log.severe(
            'cant build security context object: $compiler ${arguments.join(
                ' ')}:\n$errorMessage\n');
      }
    }
    
    runner.releaseDirectoryForSubmission(Submission());
  }
}
