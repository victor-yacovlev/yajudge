import 'dart:async';
import 'dart:io' as io;

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
  final GradingLimits? overrideLimits;
  final SecurityContext defaultSecurityContext;
  final CompilersConfig compilersConfig;
  final ServiceProperties serviceProperties;
  final bool usePidFile;
  final bool processLocalInboxOnly;

  late final ClientChannel masterServer;
  late final CourseManagementClient coursesService;
  late final SubmissionManagementClient submissionsService;
  late final GraderProperties _graderProperties;

  bool shuttingDown = false;
  int shutdownExitCode = 0;

  GraderService({
    required this.rpcProperties,
    required this.locationProperties,
    required this.identityProperties,
    required this.serviceProperties,
    required this.usePidFile,
    required this.defaultLimits,
    this.overrideLimits,
    required this.defaultSecurityContext,
    required this.compilersConfig,
    this.processLocalInboxOnly = false,
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
      if (shuttingDown) {
        if (usePidFile && serviceProperties.pidFilePath!='disabled') {
          io.File(serviceProperties.pidFilePath).deleteSync();
        }
        io.exit(shutdownExitCode);
      }
    }, (e, s) => handleGraderError(e))!
        .then((_) => serveSupervised());
  }

  Future<void> serveIncomingSubmissions() async {
    final localInboxDir = io.Directory('${locationProperties.workDir}/inbox');
    final localDoneDir = io.Directory('${locationProperties.workDir}/done');
    while (!shuttingDown) {
      bool processed = false;
      Submission submission = Submission();

      // Check submission from master server
      if (!processLocalInboxOnly) {
        submission =
        await submissionsService.takeSubmissionToGrade(_graderProperties);
        if (submission.id.toInt() > 0) {
          submission = await processSubmission(submission);
          submission = submission.copyWith((s) {
            s.graderName = _graderProperties.name;
          });
          await submissionsService.updateGraderOutput(submission);
          processed = true;
        }
      }

      // Check submissions from local file system
      if (localInboxDir.existsSync()) {
        for (final entry in localInboxDir.listSync()) {
          String name = path.basename(entry.path);
          final inboxFile = io.File('${localInboxDir.path}/$name');
          if (!localDoneDir.existsSync()) {
            localDoneDir.createSync(recursive: true);
          }
          final doneFile = io.File('${localDoneDir.path}/$name');
          final inboxData = inboxFile.readAsBytesSync();
          final localSubmission = LocalGraderSubmission.fromBuffer(inboxData);
          submission = await processSubmission(localSubmission.submission, localSubmission.gradingLimits);
          doneFile.writeAsBytesSync(submission.writeToBuffer());
          inboxFile.deleteSync();
          processed = true;
        }
      }

      // Wait and retry if there is no submissions
      if (!processed) {
        io.sleep(Duration(seconds: 2));
      }
    }
  }

  Future<Submission> processSubmission(Submission submission, [GradingLimits? overrideLimits]) async {
    final courseId = submission.course.dataId;
    final problemId = submission.problemId;

    log.info('processing submission ${submission.id} $courseId/$problemId');

    AbstractRunner runner;
    if (io.Platform.isLinux) {
      runner = ChrootedRunner(
        locationProperties: locationProperties,
        courseId: courseId,
        problemId: problemId,
      );
    }
    else {
      runner = SimpleRunner(locationProperties: locationProperties);
    }

    SubmissionProcessor processor = SubmissionProcessor(
      submission: submission,
      runner: runner,
      locationProperties: locationProperties,
      defaultLimits: defaultLimits,
      defaultSecurityContext: defaultSecurityContext,
      compilersConfig: compilersConfig,
      coursesService: coursesService,
      overrideLimits: overrideLimits,
    );

    await processor.loadProblemData();
    await processor.processSubmission();

    Submission result = processor.submission;
    log.info('done processing submission ${submission.id} with status ${result.status.name}');
    return result;
  }

  void shutdown(String reason, [bool error = false]) async {
    log.info('grader shutting down due to $reason');
    shuttingDown = true;
    shutdownExitCode = error ? 1 : 0;
  }

}
