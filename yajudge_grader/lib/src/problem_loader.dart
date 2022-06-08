import 'dart:io' as io;
import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:yajudge_common/yajudge_common.dart';
import 'abstract_runner.dart';
import 'grader_extra_configs.dart';


class ProblemLoader {
  final Submission submission;
  final GraderLocationProperties locationProperties;
  final CourseManagementClient coursesService;
  final SecurityContext defaultSecurityContext;
  final CompilersConfig compilersConfig;
  final AbstractRunner runner;
  final log = Logger('ProblemLoader');

  ProblemLoader({
    required this.submission,
    required this.coursesService,
    required this.locationProperties,
    required this.compilersConfig,
    required this.defaultSecurityContext,
    required this.runner,
  });

  Future<void> loadProblemData() async {
    final courseId = submission.course.dataId;
    final problemId = submission.problemId;
    String root = locationProperties.cacheDir;
    final problemDir = io.Directory(path.absolute(root, courseId, problemId.replaceAll(':', '/')));
    final problemTimeStampFile = io.File('${problemDir.path}/.timestamp');
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
      String buildDir = '${problemDir.path}/build';
      String testsDir = '${problemDir.path}/tests';
      io.Directory(buildDir).createSync(recursive: true);
      io.Directory(testsDir).createSync(recursive: true);
      final problemData = response.data;
      final opts = problemData.gradingOptions;
      String compileOptions = opts.extraCompileOptions.join(' ');
      String linkOptions = opts.extraLinkOptions.join(' ');
      io.File('$buildDir/.compile_options').writeAsStringSync(compileOptions);
      io.File('$buildDir/.link_options').writeAsStringSync(linkOptions);
      final codeStyles = opts.codeStyles;
      for (final codeStyle in codeStyles) {
        String fileName = codeStyle.styleFile.name;
        String suffix = codeStyle.sourceFileSuffix;
        if (suffix.startsWith('.')) {
          suffix = suffix.substring(1);
        }
        io.File('$buildDir/$fileName').writeAsBytesSync(
            codeStyle.styleFile.data);
        io.File('$buildDir/.style_$suffix').writeAsStringSync(
            codeStyle.styleFile.name);
      }
      for (final file in opts.extraBuildFiles.files) {
        io.File('$buildDir/${file.name}').writeAsBytesSync(file.data);
      }
      final customChecker = opts.customChecker;
      if (customChecker.name.isNotEmpty) {
        io.File('$buildDir/${customChecker.name}')
            .writeAsBytesSync(customChecker.data);
        String checkerName = opts.customChecker.name;
        String checkerOpts = opts.standardCheckerOpts;
        io.File('$buildDir/.checker')
            .writeAsStringSync('$checkerName\n$checkerOpts\n');
      } else {
        String checkerName = opts.standardChecker;
        String checkerOpts = opts.standardCheckerOpts;
        io.File('$buildDir/.checker')
            .writeAsStringSync('=$checkerName\n$checkerOpts\n');
      }
      final interactor = opts.interactor;
      if (interactor.name.isNotEmpty) {
        io.File('$buildDir/.interactor').writeAsStringSync(interactor.name);
        io.File('$buildDir/${interactor.name}')
            .writeAsBytesSync(interactor.data);
      }
      final coprocess = opts.coprocess;
      if (coprocess.name.isNotEmpty) {
        io.File('$buildDir/.coprocess').writeAsStringSync(coprocess.name);
        io.File('$buildDir/${coprocess.name}').writeAsBytesSync(coprocess.data);
        if (coprocess.name.endsWith('.c') || coprocess.name.endsWith('.cxx') || coprocess.name.endsWith('.cpp')) {
          final binaryName = path.basenameWithoutExtension(coprocess.name);
          await buildSupplementaryProgram(coprocess.name, binaryName, buildDir, courseId, problemId);
          io.File('$buildDir/.coprocess').writeAsStringSync(binaryName);
        }
      }
      final testsGenerator = opts.testsGenerator;
      if (testsGenerator.name.isNotEmpty) {
        io.File('$buildDir/${testsGenerator.name}').writeAsBytesSync(
            testsGenerator.data);
        io.File('$buildDir/.tests_generator').writeAsStringSync(
            testsGenerator.name);
      }

      if (opts.disableValgrind) {
        io.File('$buildDir/.disable_valgrind').createSync(recursive: true);
      }

      final List<String> disabledSanitizers = opts.disableSanitizers;
      if (disabledSanitizers.isNotEmpty) {
        io.File('$buildDir/.disable_sanitizers').writeAsStringSync(
            disabledSanitizers.join(' '));
      }

      GradingLimits limits = opts.limits;
      String limitsYaml = limits.toYamlString();
      if (limitsYaml
          .trim()
          .isNotEmpty) {
        io.File('$buildDir/.limits').writeAsStringSync(limitsYaml);
      }

      SecurityContext problemSecurityContext = opts.securityContext;
      String securityContextYaml = securityContextToYamlString(
          problemSecurityContext);
      if (securityContextYaml
          .trim()
          .isNotEmpty) {
        io.File('$buildDir/.security_context').writeAsStringSync(
            securityContextYaml);
      }
      final securityContext = mergeSecurityContext(
          defaultSecurityContext, problemSecurityContext
      );
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
          io.File('$testsDir/${stdin.name}').writeAsBytesSync(
              gzip.decode(stdin.data));
        }
        if (stdout.name.isNotEmpty) {
          io.File('$testsDir/${stdout.name}').writeAsBytesSync(
              gzip.decode(stdout.data));
        }
        if (stderr.name.isNotEmpty) {
          io.File('$testsDir/${stderr.name}').writeAsBytesSync(
              gzip.decode(stderr.data));
        }
        if (bundle.name.isNotEmpty) {
          io.File('$testsDir/${bundle.name}').writeAsBytesSync(bundle.data);
        }
        if (args.isNotEmpty) {
          String testBaseName = '$testNumber';
          if (testNumber < 10) {
            testBaseName = '0$testBaseName';
          }
          if (testNumber < 100) {
            testBaseName = '0$testBaseName';
          }
          io.File('$testsDir/$testBaseName.args').writeAsStringSync(
              args);
        }
        testNumber ++;
        testsCount ++;
      }
      io.File("$testsDir/.tests_count").writeAsStringSync('$testsCount\n');
      problemTimeStampFile.writeAsStringSync(
          '${response.lastModified.toInt()}\n');
    }
  }

  Future<void> buildSupplementaryProgram(
      String sourceName, String binaryName,
      String buildDir, String courseId, String problemId
      ) async {

    bool useCxx = sourceName.endsWith('.cxx') || sourceName.endsWith('.cpp');
    final compiler = useCxx ? compilersConfig.cxxCompiler : compilersConfig.cCompiler;
    final baseOptions = useCxx ? compilersConfig.cxxBaseOptions : compilersConfig.cBaseOptions;

    runner.createDirectoryForSubmission(Submission(id: Int64(-1), problemId: problemId));

    final arguments = baseOptions + ['-o', binaryName, sourceName];
    final process = await runner.start(
      Submission(id: Int64(-1), problemId: problemId),
      [compiler] + arguments,
      workingDirectory: '/build',
    );

    bool compilerOk = await process.ok;
    if (!compilerOk) {
      String errorMessage = await process.outputAsString;
      log.severe(
          'cant build supplementary $sourceName: $compiler ${arguments.join(
              ' ')}:\n$errorMessage\n');
    }

    runner.releaseDirectoryForSubmission(Submission(id: Int64(-1)));
  }

  Future<void> buildSecurityContextObjects(
      SecurityContext securityContext,
      String buildDir, String courseId, String problemId,
      ) async {
    String tempSourcePath = '$buildDir/.forbidden-functions-wrapper.c';

    final compiler = compilersConfig.cCompiler;
    final options = ['-c', '-fPIC'];

    runner.createDirectoryForSubmission(Submission(id: Int64(-1), problemId: problemId));

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
      String forbidSource = '$sourceHeader\n';
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
        Submission(id: Int64(-1), problemId: problemId),
        [compiler] + arguments,
        workingDirectory: '/build',
      );
      bool compilerOk = await process.ok;
      if (!compilerOk) {
        String errorMessage = await process.outputAsString;
        log.severe(
            'cant build security context object: $compiler ${arguments.join(
                ' ')}:\n$errorMessage\n');
      }
    }
    runner.releaseDirectoryForSubmission(Submission(id: Int64(-1)));
  }
}