import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:yajudge_common/yajudge_common.dart';
import 'package:yajudge_grader/src/checkers.dart';
import 'abstract_runner.dart';
import 'package:yaml/yaml.dart';

class SubmissionProcessor {
  Submission submission;
  final AbstractRunner runner;
  final Logger log = Logger('SubmissionProcessor');
  final GraderLocationProperties locationProperties;
  final GradingLimits defaultLimits;

  SubmissionProcessor({
    required this.submission,
    required this.runner,
    required this.locationProperties,
    required this.defaultLimits,
  });

  Future<void> processSubmission() async {
    try {
      runner.createDirectoryForSubmission(submission);
      if (!await checkCodeStyles()) {
        return;
      }
      if (!await buildSolution()) {
        return;
      }
      await runTests();
    } catch (error) {
      log.severe(error);
    } finally {
      runner.releaseDirectoryForSubmission(submission);
    }
  }

  List<String> solutionFileNames() {
    String solutionPath = runner.submissionPrivateDirectory(submission)+'/build';
    return io.File(solutionPath+'/.solution_files').readAsStringSync().trim().split('\n');
  }

  List<String> compileOptions() {
    String solutionPath = runner.submissionProblemDirectory(submission)+'/build';
    return io.File(solutionPath+'/.compile_options').readAsStringSync().trim().split(' ');
  }

  List<String> linkOptions() {
    String solutionPath = runner.submissionProblemDirectory(submission)+'/build';
    return io.File(solutionPath+'/.link_options').readAsStringSync().trim().split(' ');
  }

  String problemChecker() {
    String solutionPath = runner.submissionProblemDirectory(submission)+'/build';
    return io.File(solutionPath+'/.checker').readAsStringSync().trim();
  }

  String styleFileName(String suffix) {
    String solutionPath = runner.submissionProblemDirectory(submission)+'/build';
    if (suffix.startsWith('.'))
      suffix = suffix.substring(1);
    String styleLinkPath = '$solutionPath/.style_$suffix';
    if (io.File(styleLinkPath).existsSync()) {
      return io.File(styleLinkPath).readAsStringSync().trim();
    }
    return '';
  }

  Future<bool> checkCodeStyles() async {
    final solutionFiles = solutionFileNames();
    for (final fileName in solutionFiles) {
      String fileSuffix = path.extension(fileName);
      String styleFile = styleFileName(fileSuffix);
      if (styleFile == '.clang-format') {
        // Run clang-format to check
        io.Process clangProcess = await runner.start(
          submission.id.toInt(),
          'clang-format',
          ['-style=file', fileName],
          workingDirectory: '/build',
        );
        int exitCode = await clangProcess.exitCode;
        List<int> clangStdout = await clangProcess.stdout.first;
        String formattedCode = utf8.decode(clangStdout).trim();
        String submissionPath = runner.submissionPrivateDirectory(submission);
        String sourcePath = path.normalize('${submissionPath}/build/${fileName}');
        String sourceCode = io.File(sourcePath).readAsStringSync().trim();
        if (formattedCode != sourceCode) {
          submission = submission.copyWith((changed) {
            changed.buildErrors = formattedCode;
            changed.status = SolutionStatus.STYLE_CHECK_ERROR;
          });
          return false;
        }
      }
    }
    return true;
  }

  Future<bool> buildSolution() {
    bool hasCMakeLists = false;
    bool hasMakefile = false;
    bool hasGoFiles = false;
    for (final file in submission.solutionFiles.files) {
      if (file.name.toLowerCase() == 'makefile') {
        hasMakefile = true;
      }
      if (file.name.toLowerCase() == 'cmakelists.txt') {
        hasCMakeLists = true;
      }
      if (file.name.toLowerCase().endsWith('.go')) {
        hasGoFiles = true;
      }
    }
    if (hasCMakeLists) {
      return buildCMakeProject();
    } else if (hasMakefile) {
      return buildMakeProject();
    } else if (hasGoFiles) {
      return buildGoProject();
    } else {
      return buildProjectFromFiles();
    }
  }

  Future<bool> buildCMakeProject() {
    throw UnimplementedError('CMake project not implemented yet');
  }

  Future<bool> buildMakeProject() {
    throw UnimplementedError('Make project not implemented yet');
  }

  Future<bool> buildGoProject() {
    throw UnimplementedError('golang project not implemented yet');
  }

  Future<bool> buildProjectFromFiles() async {
    bool hasCFiles = false;
    bool hasGnuAsmFiles = false;
    bool hasCXXFiles = false;
    for (final file in submission.solutionFiles.files) {
      if (file.name.endsWith('.S') || file.name.endsWith('.s')) {
        hasGnuAsmFiles = true;
      }
      if (file.name.endsWith('.c')) {
        hasCFiles = true;
      }
      if (file.name.endsWith('.cxx') ||
          file.name.endsWith('.cc') ||
          file.name.endsWith('.cpp')) {
        hasCXXFiles = true;
      }
    }
    String compiler = '';
    if (hasCXXFiles) {
      compiler = 'clang++';
    } else if (hasCFiles || hasGnuAsmFiles) {
      compiler = 'clang';
    }
    if (compiler.isEmpty) {
      throw UnimplementedError('dont know how to build files out of ASM/C/C++');
    }
    // bool noStdLib =
    //     problemData.gradingOptions.extraCompileOptions.contains('-nostdlib');

    var compileBaseOptions = ['-c', '-O2', '-Werror', '-g'];
    List<String> objectFiles = [];
    for (final sourceFile in submission.solutionFiles.files) {
      String suffix = path.extension(sourceFile.name);
      if (!['.S', '.s', '.c', '.cpp', '.cxx', '.cc'].contains(suffix)) continue;
      String objectFileName = sourceFile.name + '.o';
      final compilerArguments = compileBaseOptions +
          compileOptions() +
          ['-o', objectFileName, sourceFile.name];
      io.Process compilerProcess = await runner.start(
        submission.id.toInt(),
        compiler,
        compilerArguments,
        workingDirectory: '/build',
      );
      int compilerExitCode = await compilerProcess.exitCode;
      if (compilerExitCode != 0) {
        List<int> stdout = await compilerProcess.stdout.first;
        List<int> stderr = await compilerProcess.stderr.first;
        String message = utf8.decode(stderr) + utf8.decode(stdout);
        log.fine('cant compile ${sourceFile.name} from ${submission.id}: $message');
        submission = submission.copyWith((changed) {
          changed.status = SolutionStatus.COMPILATION_ERROR;
          changed.buildErrors = message;
        });
        return false;
      } else {
        log.fine('successfully compiled ${sourceFile.name} from ${submission.id}');
        objectFiles.add(objectFileName);
      }
    }
    final linkerArguments = ['-o', 'solution'] +
        linkOptions() +
        objectFiles;
    io.Process linkerProcess = await runner.start(
      submission.id.toInt(),
      compiler,
      linkerArguments,
      workingDirectory: '/build'
    );
    int linkerExitCode = await linkerProcess.exitCode;
    if (linkerExitCode != 0) {
      List<int> stdout = await linkerProcess.stdout.first;
      List<int> stderr = await linkerProcess.stderr.first;
      String message = utf8.decode(stderr) + utf8.decode(stdout);
      log.fine('cant link ${submission.id}: $message');
      submission = submission.copyWith((changed) {
        changed.status = SolutionStatus.COMPILATION_ERROR;
        changed.buildErrors = message;
      });
    } else {
      log.fine('successfully linked ${submission.id}');
    }
    return true;
  }

  Future<void> runTests() async {
    String testsPath = runner.submissionWorkingDirectory(submission)+'/tests';
    bool hasRuntimeError = false;
    bool hasTimeLimit = false;
    bool hasWrongAnswer = false;
    List<TestResult> testResults = [];
    for (int i=1; i<=999; i++) {
      String baseName = '$i';
      if (i < 10)
        baseName = '0' + baseName;
      if (i < 100)
        baseName = '0' + baseName;
      bool datExists = io.File('$testsPath/$baseName.dat').existsSync();
      bool ansExists = io.File('$testsPath/$baseName.ans').existsSync();
      bool dirExists = io.Directory('$testsPath/$baseName.dir').existsSync();
      if (datExists || ansExists || dirExists) {
        TestResult result = await processTest(baseName);
        if (!result.standardMatch)
          hasWrongAnswer = true;
        if (result.timeLimit)
          hasTimeLimit = true;
        if (result.signalKilled > 0 && !result.timeLimit)
          hasRuntimeError = true;
        testResults.add(result);
      } else {
        break;
      }
    }
    SolutionStatus newStatus = submission.status;
    if (hasRuntimeError) {
      newStatus = SolutionStatus.RUNTIME_ERROR;
    }
    else if (hasTimeLimit) {
      newStatus = SolutionStatus.TIME_LIMIT;
    }
    else if (hasWrongAnswer) {
      newStatus = SolutionStatus.WRONG_ANSWER;
    } else {
      newStatus = SolutionStatus.OK;
    }
    submission = submission.copyWith((s) {
      s.status = newStatus;
      s.testResult.addAll(testResults);
    });
  }

  GradingLimits getLimitsForProblem() {
    String limitsPath = path.absolute(
      locationProperties.coursesCacheDir,
      submission.course.dataId,
      submission.problemId,
      '.limits'
    );
    GradingLimits limits = defaultLimits;
    final limitsFile = io.File(limitsPath);
    if (limitsFile.existsSync()) {
      YamlMap config = parseYamlConfig(limitsPath);
      limits = limits.copyWith((l) {
        if (config['real_time_limit_sec'] is int)
          l.cpuTimeLimitSec = Int64(config['real_time_limit_sec'] as int);
        if (config['proc_count_limit'] is int)
          l.procCountLimit = Int64(config['proc_count_limit'] as int);
      });
    }
    return limits;
  }

  Future<TestResult> processTest(String testBaseName) async {
    log.info('running test $testBaseName for submission ${submission.id}');
    String testsPath = runner.submissionWorkingDirectory(submission)+'/tests';
    final testDir = io.Directory('$testsPath/$testBaseName.dir');
    String wd = testDir.existsSync() ? '/tests/$testBaseName.dir' : '/build';
    final argsFile = io.File('$testsPath/$testBaseName.args');
    List<String> arguments = argsFile.existsSync()? argsFile.readAsStringSync().trim().split(' ') : [];
    GradingLimits limits = getLimitsForProblem();
    List<int>? stdinData;
    final stdinFile = io.File('$testsPath/$testBaseName.dat');
    if (stdinFile.existsSync()) {
      stdinData = stdinFile.readAsBytesSync();
    }
    io.Process solutionProcess = await runner.start(submission.id.toInt(), '/build/solution', arguments,
      workingDirectory: wd,
      limits: limits,
    );
    bool killedByTimeout = false;
    final timer = Timer(Duration(seconds: limits.realTimeLimitSec.toInt()), () {
      solutionProcess.kill(io.ProcessSignal.sigkill);
      killedByTimeout = true;
      log.fine('submission ${submission.id} killed by timeout ${limits.realTimeLimitSec} on test $testBaseName');
    });
    if (stdinData != null) {
      solutionProcess.stdin.write(stdinData);
      solutionProcess.stdin.close();
    }
    List<int> stdout = [];
    List<int> stderr = [];
    final maxStdoutBytes = limits.stdoutSizeLimitMb.toInt() * 1024 * 1024;
    final maxStderrBytes = limits.stderrSizeLimitMb.toInt() * 1024 * 1024;
    solutionProcess.stdout.forEach((List<int> chunk) {
      if (stdout.length + chunk.length <= maxStdoutBytes) {
        stdout.addAll(chunk);
      }
    });
    solutionProcess.stderr.forEach((List<int> chunk) {
      if (stderr.length + chunk.length <= maxStderrBytes) {
        stderr.addAll(chunk);
      }
    });
    int exitStatus = await solutionProcess.exitCode;
    timer.cancel();
    final stdoutFile = io.File('$testsPath/$testBaseName.stdout');
    final stderrFile = io.File('$testsPath/$testBaseName.stderr');
    stdoutFile.writeAsBytesSync(stdout);
    stderrFile.writeAsBytesSync(stderr);
    bool resultMatch = false;
    int signalKilled = 0;
    if (exitStatus >= 0) {
      List<int> referenceStdout = [];
      final ansFile = io.File('$testsPath/$testBaseName.ans');
      if (ansFile.existsSync()) {
        referenceStdout = ansFile.readAsBytesSync();
      }
      log.fine('submission ${submission.id} exited with $exitStatus on test $testBaseName');
      resultMatch = runChecker(stdout, stdoutFile.path, referenceStdout, '$testsPath/$testBaseName.ans', wd);
    }
    else if (exitStatus < 0) {
      signalKilled = -exitStatus;
      log.fine('submission ${submission.id} killed by signal $signalKilled on test $testBaseName');
      exitStatus = 0;
    }
    return TestResult(
      testNumber: int.parse(testBaseName, radix: 10),
      status: exitStatus,
      stderr: utf8.decode(stderr),
      stdout: utf8.decode(stdout),
      timeLimit: killedByTimeout,
      standardMatch: resultMatch,
      signalKilled: signalKilled,
    );
  }

  bool runChecker(List<int> observed, String observedPath, List<int> reference, String referencePath, String wd) {
    String checkerName = problemChecker();
    wd = path.normalize(
        path.absolute(runner.submissionWorkingDirectory(submission)+'/'+wd)
    );
    observedPath = path.normalize(
      path.absolute(observedPath)
    );
    referencePath = path.normalize(
      path.absolute(referencePath)
    );
    AbstractChecker checker;
    if (checkerName.startsWith('=')) {
      String standardCheckerName = checkerName.substring(1);
      return true; // TODO implement me
    }
    else if (checkerName.endsWith('.py')) {
      String solutionPath = runner.submissionProblemDirectory(submission)+'/build';
      String checkerPy = path.normalize(
          path.absolute(solutionPath + '/' + checkerName)
      );
      checker = PythonChecker(checkerPy: checkerPy);
    } else {
      throw UnimplementedError('checker not supported: $checkerName');
    }
    String options = '';
    if (checker.useFiles) {
      return checker.matchFiles(observedPath, referencePath, wd, options);
    } else {
      return checker.matchData(observed, reference, wd, '');
    }
  }

}
