import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:posix/posix.dart' as posix;
import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:yajudge_common/yajudge_common.dart';
import 'checkers.dart';
import 'grader_extra_configs.dart';
import 'abstract_runner.dart';
import 'package:yaml/yaml.dart';

class SubmissionProcessor {
  Submission submission;
  final AbstractRunner runner;
  final Logger log = Logger('SubmissionProcessor');
  final GraderLocationProperties locationProperties;
  final GradingLimits defaultLimits;
  final CompilersConfig compilersConfig;
  String plainBuildTarget = '';
  String sanitizersBuildTarget = '';
  bool runTargetIsScript = false;
  String targetInterpreter = '';
  bool disableValgrindAndSanitizers = false;

  SubmissionProcessor({
    required this.submission,
    required this.runner,
    required this.locationProperties,
    required this.defaultLimits,
    required this.compilersConfig,
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

  int problemTestsCount() {
    String solutionPath = runner.submissionProblemDirectory(submission)+'/tests';
    return int.parse(io.File(solutionPath+'/.tests_count').readAsStringSync().trim());
  }

  String problemTestsGenerator() {
    String solutionPath = runner.submissionProblemDirectory(submission)+'/build';
    final generatorFile = io.File(solutionPath+'/.tests_generator');
    if (generatorFile.existsSync()) {
      return generatorFile.readAsStringSync().trim();
    } else {
      return '';
    }
  }

  bool disableProblemValgrind() {
    String solutionPath = runner.submissionProblemDirectory(submission)+'/build';
    return io.File(solutionPath+'/.disable_valgrind').existsSync();
  }

  bool disableProblemSanitizers() {
    String solutionPath = runner.submissionProblemDirectory(submission)+'/build';
    return io.File(solutionPath+'/.disable_sanitizers').existsSync();
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
          ['clang-format', '-style=file', fileName],
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

  Future<bool> buildSolution() async {
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
      bool plainOk = await buildProjectFromFiles(false);
      bool sanitizersOk = true;
      if (compilersConfig.enableSanitizers) {
        final buildOptions = compileOptions() + linkOptions();
        if (!buildOptions.contains('-nostdlib') && !disableProblemSanitizers()) {
          sanitizersOk = await buildProjectFromFiles(true);
        }
      }
      return plainOk && sanitizersOk;
    }
  }

  Future<bool> buildCMakeProject() {
    throw UnimplementedError('CMake project not implemented yet');
  }

  Future<bool> buildMakeProject() async {
    final buildDir = io.Directory(runner.submissionPrivateDirectory(submission)+'/build');
    DateTime beforeMake = DateTime.now();
    io.sleep(Duration(milliseconds: 250));
    io.Process compilerProcess = await runner.start(
      submission.id.toInt(),
      ['make'],
      workingDirectory: '/build',
    );
    List<int> stdout = [];
    List<int> stderr = [];
    await compilerProcess.stdout.listen((chunk) => stdout.addAll(chunk)).asFuture();
    await compilerProcess.stderr.listen((chunk) => stderr.addAll(chunk)).asFuture();
    int compilerExitCode = await compilerProcess.exitCode;
    if (compilerExitCode != 0) {
      String message = utf8.decode(stderr) + utf8.decode(stdout);
      log.fine('cant build Makefile project from ${submission.id}:\n$message');
      io.File(buildDir.path+'/make.log').writeAsStringSync(message);
      submission = submission.copyWith((changed) {
        changed.status = SolutionStatus.COMPILATION_ERROR;
        changed.buildErrors = message;
      });
      return false;
    } else {
      log.fine('successfully compiled Makefile project from ${submission.id}');
    }
    final entriesAfterMake = buildDir.listSync(recursive: true);
    List<String> newExecutables = [];
    for (final entry in entriesAfterMake) {
      String entryPath = entry.path;
      DateTime modified = entry.statSync().modified;
      if (modified.millisecondsSinceEpoch <= beforeMake.millisecondsSinceEpoch) {
        continue;
      }
      if (0 == posix.access(entryPath, posix.X_OK)) {
        entryPath = entryPath.substring(buildDir.path.length+1);
        newExecutables.add(entryPath);
      }
    }
    if (newExecutables.isEmpty) {
      String message = 'no executables created by make in Makefile project from ${submission.id}';
      log.fine(message);
      io.File(buildDir.path+'/make.log').writeAsStringSync(message);
      submission = submission.copyWith((changed) {
        changed.status = SolutionStatus.COMPILATION_ERROR;
        changed.buildErrors = message;
      });
      return false;
    }
    if (newExecutables.length > 1) {
      String message = 'several executables created by make in Makefile project from ${submission.id}: $newExecutables}';
      log.fine(message);
      io.File(buildDir.path+'/make.log').writeAsStringSync(message);
      submission = submission.copyWith((changed) {
        changed.status = SolutionStatus.COMPILATION_ERROR;
        changed.buildErrors = message;
      });
      return false;
    }
    plainBuildTarget = '/build/'+newExecutables.first;
    disableValgrindAndSanitizers = true;
    return true;
  }

  Future<bool> buildGoProject() {
    throw UnimplementedError('golang project not implemented yet');
  }

  GradingLimits getProblemLimits(bool withValgrindAjustment) {
    GradingLimits limits = defaultLimits;
    final limitsFile = io.File(runner.submissionProblemDirectory(submission)+'/build/.limits');
    if (limitsFile.existsSync()) {
      YamlMap conf = loadYaml(limitsFile.readAsStringSync());
      limits = mergeLimitsFromYaml(limits, conf);
    }
    if (withValgrindAjustment) {
      return compilersConfig.applyValgrindToGradingLimits(limits);
    }
    else {
      return limits;
    }
  }

  Future<bool> buildProjectFromFiles(bool withSanitizers) async {
    bool hasCFiles = false;
    bool hasGnuAsmFiles = false;
    bool hasCXXFiles = false;
    List<String> scriptFiles = [];
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
      if (file.name.endsWith('.sh') || file.name.endsWith('.py')) {
        scriptFiles.add('/build/${file.name}');
      }
    }
    String compiler = '';
    List<String> compilerBaseOptions = [];
    List<String> sanitizerOptions = withSanitizers? compilersConfig.sanitizersOptions : [];
    String objectSuffix = withSanitizers? '.san.o' : '.o';
    String targetName = withSanitizers? 'solution-san' : 'solution';
    if (hasCXXFiles) {
      compiler = compilersConfig.cxxCompiler;
      compilerBaseOptions = compilersConfig.cBaseOptions;
    } else if (hasCFiles || hasGnuAsmFiles) {
      compiler = compilersConfig.cCompiler;
      compilerBaseOptions = compilersConfig.cxxBaseOptions;
    }
    if (compiler.isEmpty && scriptFiles.isEmpty) {
      throw UnimplementedError('dont know how to build files out of ASM/C/C++');
    }
    if (compiler.isEmpty && scriptFiles.isNotEmpty) {
      if (scriptFiles.length > 1) {
        throw Exception('several script files present, dont know which to run');
      }
      String scriptName = scriptFiles.first;
      final scriptFile = io.File(
          path.normalize(path.absolute(runner.submissionPrivateDirectory(submission)
              + '/$scriptName'
          )));
      final lines = scriptFile.readAsLinesSync();
      String interpreter = '';
      if (lines.length > 0) {
        String firstLine = lines.first;
        if (firstLine.startsWith('#!')) {
          interpreter = firstLine.substring(2);
        }
      }
      if (interpreter.isEmpty) {
        if (scriptName.endsWith('.sh'))
          interpreter = '/usr/bin/env bash';
        if (scriptName.endsWith('.py'))
          interpreter = '/usr/bin/env python3';
      }
      if (interpreter.isEmpty) {
        throw UnimplementedError('dont know how to run $scriptName');
      }
      plainBuildTarget = path.normalize(path.absolute(runner.submissionRootPrefix(submission)+'/$scriptName'));
      targetInterpreter = interpreter;
      runTargetIsScript = true;
      return true;
    }
    List<String> objectFiles = [];
    final buildDir = io.Directory(runner.submissionPrivateDirectory(submission)+'/build');
    for (final sourceFile in submission.solutionFiles.files) {
      String suffix = path.extension(sourceFile.name);
      if (!['.S', '.s', '.c', '.cpp', '.cxx', '.cc'].contains(suffix)) continue;
      String objectFileName = sourceFile.name + objectSuffix;
      final compilerArguments =
              ['-c'] +
              compilerBaseOptions +
              sanitizerOptions +
              ['-o', objectFileName] +
              compileOptions() +
              [sourceFile.name];
      final compilerCommand = [compiler] + compilerArguments;
      io.Process compilerProcess = await runner.start(
        submission.id.toInt(),
        compilerCommand,
        workingDirectory: '/build',
      );
      List<int> stdout = [];
      List<int> stderr = [];
      await compilerProcess.stdout.listen((chunk) => stdout.addAll(chunk)).asFuture();
      await compilerProcess.stderr.listen((chunk) => stderr.addAll(chunk)).asFuture();
      int compilerExitCode = await compilerProcess.exitCode;
      if (compilerExitCode != 0) {
        String message = utf8.decode(stderr) + utf8.decode(stdout);
        io.File(buildDir.path+'/compile.log').writeAsStringSync(message);
        log.fine('cant compile ${sourceFile.name} from ${submission.id}: ${compilerCommand.join(' ')}\n$message');
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
    final linkerArguments = ['-o', targetName] +
        sanitizerOptions +
        linkOptions() +
        objectFiles;
    final linkerCommand = [compiler] + linkerArguments;
    io.Process linkerProcess = await runner.start(
      submission.id.toInt(),
      linkerCommand,
      workingDirectory: '/build'
    );
    List<int> stdout = [];
    List<int> stderr = [];
    await linkerProcess.stdout.listen((chunk) => stdout.addAll(chunk)).asFuture();
    await linkerProcess.stderr.listen((chunk) => stderr.addAll(chunk)).asFuture();
    int linkerExitCode = await linkerProcess.exitCode;
    if (linkerExitCode != 0) {
      String message = utf8.decode(stderr) + utf8.decode(stdout);
      log.fine('cant link ${submission.id}: ${linkerCommand.join(' ')}\n$message');
      io.File(buildDir.path+'/compile.log').writeAsStringSync(message);
      submission = submission.copyWith((changed) {
        changed.status = SolutionStatus.COMPILATION_ERROR;
        changed.buildErrors = message;
      });
      return false;
    } else {
      log.fine('successfully linked target $targetName for ${submission.id}');
    }
    if (withSanitizers)
      sanitizersBuildTarget = '/build/' + targetName;
    else
      plainBuildTarget = '/build/' + targetName;
    return true;
  }

  int prepareSubmissionTests(String targetPrefix) {
    String testsPath = runner.submissionWorkingDirectory(submission)+'/tests';
    final runsDir = io.Directory(runner.submissionWorkingDirectory(submission)+'/runs/$targetPrefix/');
    runsDir.createSync(recursive: true);

    // Unpack .tgz bundles if any exists
    for (int i=1; i<=problemTestsCount(); i++) {
      String testBaseName = '$i';
      if (i < 10)
        testBaseName = '0' + testBaseName;
      if (i < 100)
        testBaseName = '0' + testBaseName;
      final testBundle = io.File('$testsPath/$testBaseName.tgz');
      if (testBundle.existsSync()) {
        io.Process.runSync('tar', ['zxf', testBundle.path], workingDirectory: runsDir.path);
      }
      else {
        break;
      }
    }

    // Generate tests if script provided
    String testsGenerator = problemTestsGenerator();
    if (testsGenerator.isEmpty) {
      return problemTestsCount();
    }

    if (testsGenerator.endsWith('.py')) {
      String binDir = path.dirname(io.Platform.script.path);
      String pyWrapper = path.normalize(path.absolute(binDir, '../libexec/', 'tests_generator_wrapper.py'));
      final arguments = [
        pyWrapper,
        runner.submissionProblemDirectory(submission)+'/build/$testsGenerator',
        runsDir.path,
      ];
      final processResult = io.Process.runSync('python3', arguments, runInShell: true);
      if (processResult.exitCode != 0) {
        String message = processResult.stdout.toString() + processResult.stderr.toString();
        log.severe('tests generator $testsGenerator failed: $message');
        return 0;
      }
      return int.parse(io.File(runsDir.path+'/.tests_count').readAsStringSync().trim());
    }
    else {
      throw UnimplementedError('Tests generators other than Python not supported yet: $testsGenerator');
    }
  }

  Future<void> runTests() async {
    String testsPath = runner.submissionWorkingDirectory(submission)+'/tests';
    String runsPath = runner.submissionWorkingDirectory(submission)+'/runs';
    bool hasRuntimeError = false;
    bool hasTimeLimit = false;
    bool hasWrongAnswer = false;
    bool hasValgrindErrors = false;
    List<TestResult> testResults = [];
    GradingLimits plainLimits = getProblemLimits(false);
    GradingLimits valgrindLimits = getProblemLimits(true);

    int testsCount = 0;

    bool runSanitizersTarget =
        !disableValgrindAndSanitizers &&
        !disableProblemSanitizers() &&
        !runTargetIsScript &&
        compilersConfig.enableSanitizers &&
        sanitizersBuildTarget.isNotEmpty
    ;
    final sanitizersTargetPrefix = 'with-sanitizers';
    if (runSanitizersTarget) {
      testsCount = prepareSubmissionTests(sanitizersTargetPrefix);
    }

    bool runValgrindTarget =
        !disableValgrindAndSanitizers &&
        !disableProblemValgrind() &&
        !runTargetIsScript &&
        compilersConfig.enableValgrind &&
        plainBuildTarget.isNotEmpty
    ;
    final valgrindTargetPrefix = 'valgrind';
    if (runValgrindTarget) {
      testsCount = prepareSubmissionTests(valgrindTargetPrefix);
    }

    bool runScriptTarget = runTargetIsScript;
    final scriptTargetPrefix = 'script';
    if (runScriptTarget) {
      testsCount = prepareSubmissionTests(scriptTargetPrefix);
    }

    bool runPlainTarget = !runSanitizersTarget && !runValgrindTarget && !runScriptTarget;
    final plainTargetPrefix = 'plain';
    if (runPlainTarget) {
      testsCount = prepareSubmissionTests(plainTargetPrefix);
    }

    for (int i=1; i<=testsCount; i++) {
      String baseName = '$i';
      if (i < 10)
        baseName = '0' + baseName;
      if (i < 100)
        baseName = '0' + baseName;

      List<TestResult> targetResults = [];

      if (runSanitizersTarget) {
        TestResult result = await processTest(
          i, sanitizersTargetPrefix,
          [sanitizersBuildTarget],
          'with sanitizers',
          baseName,
          plainLimits,
        );
        targetResults.add(result);
      }

      if (runValgrindTarget) {
        final valgrindCommandLine = [
          'valgrind', '--tool=memcheck', '--leak-check=full',
          '--show-leak-kinds=all', '--track-origins=yes',
          '--log-file=/runs/valgrind/$baseName.valgrind',
          plainBuildTarget
        ];
        TestResult result = await processTest(
          i, valgrindTargetPrefix,
          valgrindCommandLine,
          'with valgrind',
          baseName,
          valgrindLimits
        );
        final valgrindOut = io.File('$runsPath/valgrind/$baseName.valgrind').readAsStringSync();
        int valgrindErrors = 0;
        final rxErrorsSummary = RegExp(r'==\d+== ERROR SUMMARY: (\d+) errors');
        final matchEntries = List<RegExpMatch>.from(rxErrorsSummary.allMatches(valgrindOut));
        if (matchEntries.isNotEmpty) {
          RegExpMatch match = matchEntries.first;
          String matchGroup = match.group(1)!;
          valgrindErrors = int.parse(matchGroup);
        }
        if (valgrindErrors > 0) {
          result = result.copyWith((r) {
            r.valgrindErrors = valgrindErrors;
            r.valgrindOutput = valgrindOut;
          });
        }
        targetResults.add(result);
      }

      if (runPlainTarget) {
        TestResult result = await processTest(
          i, plainTargetPrefix,
          [plainBuildTarget],
          'no sanitizers, no valgrind',
          baseName,
          plainLimits,
        );
        targetResults.add(result);
      }

      if (runTargetIsScript) {
        TestResult result = await processTest(
          i, scriptTargetPrefix,
          targetInterpreter.split(' ') + [plainBuildTarget],
          'script run',
          baseName,
          plainLimits,
        );
        targetResults.add(result);
      }

      hasWrongAnswer = targetResults.any((element) => !element.standardMatch);
      hasTimeLimit = targetResults.any((element) => element.killedByTimer);
      hasRuntimeError = targetResults.any((element) => element.signalKilled>0 && !element.killedByTimer);
      hasValgrindErrors = targetResults.any((element) => element.valgrindErrors>0);
      testResults.addAll(targetResults);
    }

    SolutionStatus newStatus = submission.status;
    if (hasRuntimeError) {
      newStatus = SolutionStatus.RUNTIME_ERROR;
    }
    else if (hasValgrindErrors) {
      newStatus = SolutionStatus.VALGRIND_ERRORS;
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

  Future<TestResult> processTest(int testNumber, String runsDirPrefix, List<String> firstArgs, String description, String testBaseName, GradingLimits limits) async {
    log.info('running test $testBaseName ($description) for submission ${submission.id}');
    String testsPath = runner.submissionWorkingDirectory(submission)+'/tests';
    final runsDir = io.Directory(runner.submissionWorkingDirectory(submission)+'/runs/$runsDirPrefix/');
    String wd;
    if (io.Directory(runsDir.path+'/$testBaseName.dir').existsSync()) {
      wd = '/runs/$runsDirPrefix/$testBaseName.dir';
    }
    else {
      wd = '/runs/$runsDirPrefix';
    }

    List<String> arguments = [];
    final problemArgsFile = io.File('$testsPath/$testBaseName.args');
    final targetArgsFile = io.File('${runsDir.path}/$testBaseName.inf');
    if (targetArgsFile.existsSync()) {
      // file generated by tests generator
      String line = targetArgsFile.readAsStringSync().trim();
      final parts = line.split('=');
      if (parts.length > 1) {
        String value = parts[1].trimLeft();
        String key = parts[0].trimRight();
        if (key == 'params') {
          arguments = value.split(' ');
        }
      }
    }
    else if (problemArgsFile.existsSync()) {
      // already parsed arguments file
      arguments = problemArgsFile.readAsStringSync().trim().split(' ');
    }

    List<int> stdinData = [];
    final problemStdinFile = io.File('$testsPath/$testBaseName.dat');
    final targetStdinFile = io.File('${runsDir.path}/$testBaseName.dat');
    String stdinFilePath = '';
    if (targetStdinFile.existsSync()) {
      stdinData = targetStdinFile.readAsBytesSync();
      stdinFilePath = targetStdinFile.path;
    }
    else if (problemStdinFile.existsSync()) {
      stdinData = problemStdinFile.readAsBytesSync();
      stdinFilePath = problemStdinFile.path;
    }
    io.Process solutionProcess = await runner.start(submission.id.toInt(), firstArgs + arguments,
      workingDirectory: wd,
      limits: limits,
      runTargetIsScript: runTargetIsScript,
    );
    bool killedByTimeout = false;
    final timer = Timer(Duration(seconds: limits.realTimeLimitSec.toInt()), () {
      solutionProcess.kill(io.ProcessSignal.sigkill);
      killedByTimeout = true;
      log.fine('submission ${submission.id} ($description) killed by timeout ${limits.realTimeLimitSec} on test $testBaseName');
    });
    if (stdinData.isNotEmpty) {
      solutionProcess.stdin.add(stdinData);
      await solutionProcess.stdin.flush();
      solutionProcess.stdin.close();
    }
    List<int> stdout = [];
    List<int> stderr = [];
    final maxStdoutBytes = limits.stdoutSizeLimitMb.toInt() * 1024 * 1024;
    final maxStderrBytes = limits.stderrSizeLimitMb.toInt() * 1024 * 1024;
    final stdoutListener = solutionProcess.stdout.listen((List<int> chunk) {
      if (stdout.length + chunk.length <= maxStdoutBytes) {
        stdout.addAll(chunk);
      }
    }).asFuture();
    final stderrListener = solutionProcess.stderr.listen((List<int> chunk) {
      if (stderr.length + chunk.length <= maxStderrBytes) {
        stderr.addAll(chunk);
      }
    }).asFuture();
    int exitStatus = await solutionProcess.exitCode;
    timer.cancel();
    await stdoutListener;
    await stderrListener;
    final stdoutFile = io.File('${runsDir.path}/$testBaseName.stdout');
    final stderrFile = io.File('${runsDir.path}/$testBaseName.stderr');
    stdoutFile.writeAsBytesSync(stdout);
    stderrFile.writeAsBytesSync(stderr);
    String resultCheckerMessage = '';
    int signalKilled = 0;
    if (exitStatus >= 0) {
      List<int> referenceStdout = [];
      final problemAnsFile = io.File('$testsPath/$testBaseName.ans');
      final targetAnsFile = io.File('${runsDir.path}/$testBaseName.ans');
      String referencePath = '';
      if (targetAnsFile.existsSync()) {
        referenceStdout = targetAnsFile.readAsBytesSync();
        referencePath = targetAnsFile.path;
      }
      else if (problemAnsFile.existsSync()) {
        referenceStdout = problemAnsFile.readAsBytesSync();
        referencePath = problemAnsFile.path;
      }
      log.fine('submission ${submission.id} ($description) exited with $exitStatus on test $testBaseName');
      resultCheckerMessage = runChecker(arguments,
          stdinData==null? [] : stdinData, stdinFilePath,
          stdout, stdoutFile.path,
          referenceStdout, referencePath,
          wd);
      final checkerOutFile = io.File('${runsDir.path}/$testBaseName.checker');
      checkerOutFile.writeAsStringSync(resultCheckerMessage);
    }
    else if (exitStatus < 0) {
      signalKilled = -exitStatus;
      log.fine('submission ${submission.id} ($description) killed by signal $signalKilled on test $testBaseName');
      exitStatus = 0;
    }
    return TestResult(
      testNumber: testNumber,
      target: runsDirPrefix,
      status: exitStatus,
      stderr: utf8.decode(stderr),
      stdout: utf8.decode(stdout),
      killedByTimer: killedByTimeout,
      standardMatch: resultCheckerMessage.isEmpty,
      checkerOutput: resultCheckerMessage,
      signalKilled: signalKilled,
    );
  }

  String runChecker(List<String> args,
      List<int> stdin, String stdinName,
      List<int> stdout, String stdoutName,
      List<int> reference, String referenceName,
      String wd)
  {
    final checkerData = problemChecker().trim().split('\n');
    final checkerName = checkerData[0];
    final checkerOpts = checkerData.length > 1? checkerData[1] : '';
    wd = path.normalize(
        path.absolute(runner.submissionWorkingDirectory(submission)+'/'+wd)
    );
    if (stdinName.isNotEmpty) {
      stdinName = path.normalize(path.absolute(stdinName));
    }
    if (stdoutName.isNotEmpty) {
      stdoutName = path.normalize(path.absolute(stdoutName));
    }
    if (referenceName.isNotEmpty) {
      referenceName = path.normalize(path.absolute(referenceName));
    }

    AbstractChecker checker;
    if (checkerName.startsWith('=')) {
      String standardCheckerName = checkerName.substring(1);
      checker = StandardCheckersFactory.getChecker(standardCheckerName);
    }
    else if (checkerName.endsWith('.py')) {
      String solutionPath = runner.submissionProblemDirectory(submission)+'/build';
      String checkerPy = path.normalize(
          path.absolute(solutionPath + '/' + checkerName)
      );
      checker = PythonChecker(checkerPy: checkerPy);
    }
    else {
      throw UnimplementedError('dont know how to handle checker $checkerName');
    }
    String root = runner.submissionFileSystemRootPrefix(submission);
    if (checker.useFiles) {
      return checker.matchFiles(args, stdinName, stdoutName, referenceName, wd, root, checkerOpts);
    } else {
      return checker.matchData(args, stdin, stdout, reference, wd, root, checkerOpts);
    }
  }

}
