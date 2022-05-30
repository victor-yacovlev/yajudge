// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:posix/posix.dart' as posix;
import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:yajudge_common/yajudge_common.dart';
import 'assets_loader.dart';
import 'checkers.dart';
import 'grader_extra_configs.dart';
import 'abstract_runner.dart';
import 'package:yaml/yaml.dart';

import 'interactors.dart';

class SubmissionProcessor {
  Submission submission;
  final AbstractRunner runner;
  final Logger log = Logger('SubmissionProcessor');
  final GraderLocationProperties locationProperties;
  final GradingLimits defaultLimits;
  final GradingLimits? overrideLimits;
  final SecurityContext defaultSecurityContext;
  final CompilersConfig compilersConfig;
  final InteractorFactory interactorFactory;

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
    this.overrideLimits,
    required this.defaultSecurityContext,
    required this.compilersConfig,
  }): interactorFactory = InteractorFactory(locationProperties: locationProperties);


  Future<void> processSubmission() async {
    try {
      log.fine('started processing ${submission.id}');
      runner.createDirectoryForSubmission(submission);
      if (!await checkCodeStyles()) {
        return;
      }
      if (!await buildSolution()) {
        return;
      }
      await runTests();
      log.fine('submission ${submission.id} done with status ${submission.status.value} (${submission.status.name})');
    } catch (error) {
      log.severe(error);
    } finally {
      runner.releaseDirectoryForSubmission(submission);
    }
  }

  List<String> solutionFileNames() {
    String solutionPath = '${runner.submissionPrivateDirectory(submission)}/build';
    return io.File('$solutionPath/.solution_files').readAsStringSync().trim().split('\n');
  }

  List<String> compileOptions() {
    String solutionPath = '${runner.submissionProblemDirectory(submission)}/build';
    return io.File('$solutionPath/.compile_options').readAsStringSync().trim().split(' ');
  }

  List<String> linkOptions() {
    String solutionPath = '${runner.submissionProblemDirectory(submission)}/build';
    return io.File('$solutionPath/.link_options').readAsStringSync().trim().split(' ');
  }

  String problemChecker() {
    String solutionPath = '${runner.submissionProblemDirectory(submission)}/build';
    return io.File('$solutionPath/.checker').readAsStringSync().trim();
  }

  String interactorFilePath() {
    String solutionPath = '${runner.submissionProblemDirectory(submission)}/build';
    final interactorLinkFile = io.File('$solutionPath/.interactor');
    if (interactorLinkFile.existsSync()) {
      String interactorName = interactorLinkFile.readAsStringSync().trim();
      return '$solutionPath/$interactorName';
    }
    else {
      return '';
    }
  }

  String coprocessFilePath() {
    String solutionPath = '${runner.submissionProblemDirectory(submission)}/build';
    final coprocessLinkFile = io.File('$solutionPath/.coprocess');
    if (coprocessLinkFile.existsSync()) {
      String coprocessName = coprocessLinkFile.readAsStringSync().trim();
      return '$solutionPath/$coprocessName';
    }
    else {
      return '';
    }
  }

  int problemTestsCount() {
    String solutionPath = '${runner.submissionProblemDirectory(submission)}/tests';
    return int.parse(io.File('$solutionPath/.tests_count').readAsStringSync().trim());
  }

  String problemTestsGenerator() {
    String solutionPath = '${runner.submissionProblemDirectory(submission)}/build';
    final generatorFile = io.File('$solutionPath/.tests_generator');
    if (generatorFile.existsSync()) {
      return generatorFile.readAsStringSync().trim();
    } else {
      return '';
    }
  }

  bool disableProblemValgrind() {
    String solutionPath = '${runner.submissionProblemDirectory(submission)}/build';
    return io.File('$solutionPath/.disable_valgrind').existsSync();
  }

  List<String> disableProblemSanitizers() {
    String solutionPath = '${runner.submissionProblemDirectory(submission)}/build';
    final confFile = io.File('$solutionPath/.disable_sanitizers');
    return confFile.existsSync()? confFile.readAsStringSync().trim().split(' ') : [];
  }

  SecurityContext securityContext() {
    String solutionPath = '${runner.submissionProblemDirectory(submission)}/build';
    final confFile = io.File('$solutionPath/.security_context');
    if (confFile.existsSync()) {
      YamlMap conf = loadYaml(confFile.readAsStringSync());
      final problemSecurityContext = securityContextFromYaml(conf);
      return mergeSecurityContext(defaultSecurityContext, problemSecurityContext);
    }
    else {
      return defaultSecurityContext;
    }
  }

  String styleFileName(String suffix) {
    String solutionPath = '${runner.submissionProblemDirectory(submission)}/build';
    if (suffix.startsWith('.')) {
      suffix = suffix.substring(1);
    }
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
        final clangProcess = await runner.start(
          submission,
          ['clang-format', '-style=file', fileName],
          workingDirectory: '/build',
        );
        bool clangFormatOk = await clangProcess.ok;
        if (!clangFormatOk) {
          String message = await clangProcess.outputAsString;
          log.severe('clang-format failed: $message');
        }

        String submissionPath = runner.submissionPrivateDirectory(submission);
        String sourcePath = path.normalize('$submissionPath/build/$fileName');
        String formattedPath = '$sourcePath.formatted';
        final formattedFile = io.File(formattedPath);
        formattedFile.writeAsStringSync(await clangProcess.outputAsString);

        final diffProcess = await runner.start(
          submission,
          ['diff', fileName, '$fileName.formatted'],
          workingDirectory: '/build',
        );
        bool diffOk = await diffProcess.ok;
        String diffOut = await diffProcess.outputAsString;
        if (!diffOk) {
          submission = submission.copyWith((s) {
            s.styleErrorLog = diffOut;
            s.status = SolutionStatus.STYLE_CHECK_ERROR;
          });
          return false;
        }
      }
    }
    return true;
  }

  List<String> getSanitizersList() {
    if (disableValgrindAndSanitizers) {
      return [];
    }
    List<String> sanitizers = List.from(compilersConfig.enableSanitizers);
    List<String> disabledSanitizers = disableProblemSanitizers();
    for (String sanitizer in disabledSanitizers) {
      sanitizers.remove(sanitizer);
    }
    return sanitizers;
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
      bool plainOk = await buildProjectFromFiles([]);
      bool sanitizersOk = true;
      if (getSanitizersList().isNotEmpty) {
        final buildOptions = compileOptions() + linkOptions();
        if (!buildOptions.contains('-nostdlib')) {
          sanitizersOk = await buildProjectFromFiles(getSanitizersList());
        }
      }
      return plainOk && sanitizersOk;
    }
  }

  Future<bool> buildCMakeProject() {
    throw UnimplementedError('CMake project not implemented yet');
  }

  Future<bool> buildMakeProject() async {
    final buildDir = io.Directory('${runner.submissionPrivateDirectory(submission)}/build');
    DateTime beforeMake = DateTime.now();
    io.sleep(Duration(milliseconds: 250));
    final makeProcess = await runner.start(
      submission,
      ['make'],
      workingDirectory: '/build',
    );
    bool makeOk = await makeProcess.ok;
    if (!makeOk) {
      String message = await makeProcess.outputAsString;
      log.fine('cant build Makefile project from ${submission.id}:\n$message');
      io.File('${buildDir.path}/make.log').writeAsStringSync(message);
      submission = submission.copyWith((changed) {
        changed.status = SolutionStatus.COMPILATION_ERROR;
        changed.buildErrorLog = message;
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
      io.File('${buildDir.path}/make.log').writeAsStringSync(message);
      submission = submission.copyWith((changed) {
        changed.status = SolutionStatus.COMPILATION_ERROR;
        changed.buildErrorLog = message;
      });
      return false;
    }
    if (newExecutables.length > 1) {
      String message = 'several executables created by make in Makefile project from ${submission.id}: $newExecutables}';
      log.fine(message);
      io.File('${buildDir.path}/make.log').writeAsStringSync(message);
      submission = submission.copyWith((changed) {
        changed.status = SolutionStatus.COMPILATION_ERROR;
        changed.buildErrorLog = message;
      });
      return false;
    }
    plainBuildTarget = '/build/${newExecutables.first}';
    disableValgrindAndSanitizers = true;
    return true;
  }

  Future<bool> buildGoProject() {
    throw UnimplementedError('golang project not implemented yet');
  }

  GradingLimits getLimits(bool withValgrindAjustment) {
    GradingLimits limits = getLimitsForProblem();
    if (withValgrindAjustment) {
      return compilersConfig.applyValgrindToGradingLimits(limits);
    }
    else {
      return limits;
    }
  }

  Future<bool> buildProjectFromFiles(List<String> sanitizersToUse) async {
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
    List<String> sanitizerOptions = [];
    for (String sanitizer in sanitizersToUse) {
      sanitizerOptions.add('-fsanitize=$sanitizer');
    }
    if (sanitizersToUse.isNotEmpty) {
      sanitizerOptions.add('-fno-sanitize-recover=all');
    }
    String objectSuffix = sanitizerOptions.isNotEmpty? '.san.o' : '.o';
    String targetName = sanitizerOptions.isNotEmpty? 'solution-san' : 'solution';
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
          path.normalize(path.absolute('${runner.submissionPrivateDirectory(submission)}/$scriptName'
          )));
      final lines = scriptFile.readAsLinesSync();
      String interpreter = '';
      if (lines.isNotEmpty) {
        String firstLine = lines.first;
        if (firstLine.startsWith('#!')) {
          interpreter = firstLine.substring(2);
        }
      }
      if (interpreter.isEmpty) {
        if (scriptName.endsWith('.sh')) {
          interpreter = '/usr/bin/env bash';
        }
        if (scriptName.endsWith('.py')) {
          interpreter = '/usr/bin/env python3';
        }
      }
      if (interpreter.isEmpty) {
        throw UnimplementedError('dont know how to run $scriptName');
      }
      plainBuildTarget = path.normalize(path.absolute('${runner.submissionRootPrefix(submission)}/$scriptName'));
      targetInterpreter = interpreter;
      runTargetIsScript = true;
      return true;
    }
    List<String> objectFiles = [];
    final buildDir = io.Directory('${runner.submissionPrivateDirectory(submission)}/build');
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
      final compilerProcess = await runner.start(
        submission,
        compilerCommand,
        workingDirectory: '/build',
      );
      bool compilerOk = await compilerProcess.ok;
      if (!compilerOk) {
        String message = await compilerProcess.outputAsString;
        io.File('${buildDir.path}/compile.log').writeAsStringSync(message);
        log.fine('cant compile ${sourceFile.name} from ${submission.id}: ${compilerCommand.join(' ')}\n$message');
        submission = submission.copyWith((changed) {
          changed.status = SolutionStatus.COMPILATION_ERROR;
          changed.buildErrorLog = message;
        });
        return false;
      } else {
        log.fine('successfully compiled ${sourceFile.name} from ${submission.id}');
        objectFiles.add(objectFileName);
      }
    }
    List<String> wrapOptionsPre = [];
    List<String> wrapOptionsPost = [];
    if (!linkOptions().contains('-nostdlib') && io.Platform.isLinux) {
      final security = securityContext();
      if (security.forbiddenFunctions.isNotEmpty) {
        for (final name in security.forbiddenFunctions) {
          wrapOptionsPre.add('-Wl,--wrap=$name');
        }
        wrapOptionsPost.add('.forbidden-functions-wrapper.o');
      }
    }
    final linkerArguments = ['-o', targetName] +
        sanitizerOptions +
        wrapOptionsPre + linkOptions() + wrapOptionsPost +
        objectFiles;
    final linkerCommand = [compiler] + linkerArguments;
    final linkerProcess = await runner.start(
      submission,
      linkerCommand,
      workingDirectory: '/build'
    );
    bool linkerOk = await linkerProcess.ok;
    if (!linkerOk) {
      String message = await linkerProcess.outputAsString;
      log.fine('cant link ${submission.id}: ${linkerCommand.join(' ')}\n$message');
      io.File('${buildDir.path}/compile.log').writeAsStringSync(message);
      submission = submission.copyWith((changed) {
        changed.status = SolutionStatus.COMPILATION_ERROR;
        changed.buildErrorLog = message;
      });
      return false;
    } else {
      log.fine('successfully linked target $targetName for ${submission.id}');
    }
    if (sanitizersToUse.isNotEmpty) {
      sanitizersBuildTarget = '/build/$targetName';
    } else {
      plainBuildTarget = '/build/$targetName';
    }
    return true;
  }

  int prepareSubmissionTests(String targetPrefix) {
    String testsPath = '${runner.submissionProblemDirectory(submission)}/tests';
    final runsDir = io.Directory('${runner.submissionPrivateDirectory(submission)}/runs/$targetPrefix/');
    runsDir.createSync(recursive: true);

    // Unpack .tgz bundles if any exists
    for (int i=1; i<=problemTestsCount(); i++) {
      String testBaseName = '$i';
      if (i < 10) {
        testBaseName = '0$testBaseName';
      }
      if (i < 100) {
        testBaseName = '0$testBaseName';
      }
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
      final wrappersDir = io.Directory('${locationProperties.cacheDir}/wrappers');
      if (!wrappersDir.existsSync()) {
        wrappersDir.createSync(recursive: true);
      }
      final wrapperFile = io.File('${wrappersDir.path}/tests_generator_wrapper.py');
      if (!wrapperFile.existsSync()) {
        final content = assetsLoader.fileAsBytes('tests_generator_wrapper.py');
        wrapperFile.writeAsBytesSync(content);
      }

      final arguments = [
        wrapperFile.path,
        '${runner.submissionProblemDirectory(submission)}/build/$testsGenerator',
        runsDir.path,
      ];

      final processResult = io.Process.runSync('python3', arguments, runInShell: true);

      if (processResult.exitCode != 0) {
        String message = processResult.stdout.toString() + processResult.stderr.toString();
        log.severe('tests generator $testsGenerator failed: $message');
        return 0;
      }
      return int.parse(io.File('${runsDir.path}/.tests_count').readAsStringSync().trim());
    }
    else {
      throw UnimplementedError('Tests generators other than Python not supported yet: $testsGenerator');
    }
  }

  Future<void> runTests() async {
    bool hasRuntimeError = false;
    bool hasTimeLimit = false;
    bool hasWrongAnswer = false;
    bool hasValgrindErrors = false;
    List<TestResult> testResults = [];
    GradingLimits plainLimits = getLimits(false);
    GradingLimits valgrindLimits = getLimits(true);

    int testsCount = 0;

    bool runSanitizersTarget =
        !disableValgrindAndSanitizers &&
        getSanitizersList().isNotEmpty &&
        !runTargetIsScript &&
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
      if (i < 10) {
        baseName = '0$baseName';
      }
      if (i < 100) {
        baseName = '0$baseName';
      }

      List<TestResult> targetResults = [];
      bool hasFailedTests() {
        for (final result in targetResults) {
          if (result.status == SolutionStatus.RUNTIME_ERROR) {
            return true;
          }
        }
        return false;
      }

      bool hasFailed = false;

      if (runPlainTarget) {
        TestResult result = await processTest(
          testNumber: i,
          runsDirPrefix: plainTargetPrefix,
          firstArgs: [plainBuildTarget],
          description: 'no sanitizers, no valgrind',
          testBaseName: baseName,
          limits: plainLimits,
        );
        targetResults.add(result);
        hasFailed = hasFailedTests();
      }


      if (runSanitizersTarget && !hasFailed) {
        TestResult result = await processTest(
          testNumber: i,
          runsDirPrefix: sanitizersTargetPrefix,
          firstArgs: [sanitizersBuildTarget],
          description: 'with sanitizers',
          testBaseName: baseName,
          limits: plainLimits,
          checkSanitizersErrors: true,
        );
        targetResults.add(result);
        hasFailed = hasFailedTests();
      }

      if (runValgrindTarget && !hasFailed) {
        final valgrindCommandLine = [
          'valgrind', '--tool=memcheck', '--leak-check=full',
          '--show-leak-kinds=all', '--track-origins=yes',
          '--log-file=/runs/valgrind/$baseName.valgrind',
          plainBuildTarget
        ];
        TestResult result = await processTest(
          testNumber: i,
          runsDirPrefix: valgrindTargetPrefix,
          firstArgs: valgrindCommandLine,
          description: 'with valgrind',
          testBaseName: baseName,
          limits: valgrindLimits,
          checkValgrindErrors: true,
        );

        targetResults.add(result);
      }

      if (runTargetIsScript) {
        TestResult result = await processTest(
          testNumber: i,
          runsDirPrefix: scriptTargetPrefix,
          firstArgs: targetInterpreter.split(' ') + [plainBuildTarget],
          description: 'script run',
          testBaseName: baseName,
          limits: plainLimits,
        );
        targetResults.add(result);
      }

      hasWrongAnswer = hasWrongAnswer || targetResults.any((element) => element.status==SolutionStatus.WRONG_ANSWER);
      hasTimeLimit = hasTimeLimit || targetResults.any((element) => element.status==SolutionStatus.TIME_LIMIT);
      hasRuntimeError = hasRuntimeError || targetResults.any((element) => element.status==SolutionStatus.RUNTIME_ERROR);
      hasValgrindErrors = hasValgrindErrors || targetResults.any((element) => element.status==SolutionStatus.VALGRIND_ERRORS);
      testResults.addAll(targetResults);
      if (hasWrongAnswer||hasTimeLimit||hasRuntimeError||hasValgrindErrors) {
        break;
      }
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
      s.testResults.addAll(testResults);
    });
  }



  GradingLimits getLimitsForProblem() {
    String limitsPath = path.absolute(
      '${locationProperties.cacheDir}/${submission.course.dataId}/${submission.problemId}/build/.limits'
    );
    GradingLimits limits = defaultLimits;
    final limitsFile = io.File(limitsPath);
    if (limitsFile.existsSync()) {
      final conf = parseYamlConfig(limitsPath);
      final problemLimits = limitsFromYaml(conf);
      limits = mergeLimits(limits, problemLimits);
    }
    if (overrideLimits != null) {
      limits = mergeLimits(limits, overrideLimits!);
    }
    return limits;
  }

  List<String> parseTestInfArgumentsLine(String line) {
    String quoteSymbol = '';
    List<String> result = [];
    String currentToken = '';
    for (int i=0; i<line.length; i++) {
      String currentSymbol = line.substring(i, i+1);
      if (currentSymbol==' ' && quoteSymbol.isEmpty) {
        if (currentToken.isNotEmpty) {
          result.add(currentToken);
        }
        currentToken = '';
      }
      else if (currentSymbol=='"' && quoteSymbol!='"') {
        quoteSymbol = '"';
      }
      else if (currentSymbol=="'" && quoteSymbol!="'") {
        quoteSymbol = "'";
      }
      else if (currentSymbol == quoteSymbol) {
        quoteSymbol = '';
      }
      else {
        currentToken += currentSymbol;
      }
    }
    if (currentToken.isNotEmpty) {
      result.add(currentToken);
    }
    return result;
  }

  Future<TestResult> processTest({
    required int testNumber,
    required String runsDirPrefix,
    required List<String> firstArgs,
    required String description,
    required String testBaseName,
    required GradingLimits limits,
    bool checkValgrindErrors = false,
    bool checkSanitizersErrors = false,

  }) async {
    log.info('running test $testBaseName ($description) for submission ${submission.id}');
    String testsPath = '${runner.submissionProblemDirectory(submission)}/tests';
    final runsDir = io.Directory('${runner.submissionPrivateDirectory(submission)}/runs/$runsDirPrefix/');
    String wd;
    if (io.Directory('${runsDir.path}/$testBaseName.dir').existsSync()) {
      wd = '/runs/$runsDirPrefix/$testBaseName.dir';
    }
    else {
      wd = '/runs/$runsDirPrefix';
    }

    List<String> arguments = [];
    final problemArgsFile = io.File('$testsPath/$testBaseName.args');
    final targetArgsFile = io.File('${runsDir.path}/$testBaseName.inf');
    String argumentsLine = '';
    if (targetArgsFile.existsSync()) {
      // file generated by tests generator
      String line = targetArgsFile.readAsStringSync().trim();
      int eqPos = line.indexOf('=');
      if (eqPos > 0) {
        String key = line.substring(0, eqPos).trimRight();
        String value = line.substring(eqPos+1).trimLeft();
        if (key == 'params') {
          argumentsLine = value;
        }
      }
    }
    else if (problemArgsFile.existsSync()) {
      // already parsed arguments file
      argumentsLine = problemArgsFile.readAsStringSync().trim();
    }
    arguments = parseTestInfArgumentsLine(argumentsLine);
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

    String interactorName = interactorFilePath();
    AbstractInteractor? interactor;
    Function? interactorShutdown;

    if (interactorName.isNotEmpty) {
      interactor = interactorFactory.getInteractor(interactorName);
    }

    String coprocessName = coprocessFilePath();

    final solutionProcess = await runner.start(
      submission,
      firstArgs + arguments,
      workingDirectory: wd,
      limits: limits,
      runTargetIsScript: runTargetIsScript,
      coprocessFileName: coprocessName,
    );

    if (interactor != null) {
      interactorShutdown = await interactor.interact(solutionProcess, wd, stdinFilePath);
    }
    else {
      if (stdinData.isNotEmpty) {
        await solutionProcess.writeToStdin(stdinData);
      }
      await solutionProcess.closeStdin();
    }

    bool timeoutExceed = false;
    Timer? timer;

    void handleTimeout() {
      timeoutExceed = true;
      runner.killProcess(solutionProcess);
    }

    if (limits.realTimeLimitSec > 0) {
      final timerDuration = Duration(seconds: limits.realTimeLimitSec.toInt());
      timer = Timer(timerDuration, handleTimeout);
    }

    int exitStatus = await solutionProcess.exitCode;
    if (timer != null) {
      timer.cancel();
    }
    if (interactorShutdown != null) {
      await interactorShutdown();
    }

    List<int> stdout = await solutionProcess.stdout;
    List<int> stderr = await solutionProcess.stderr;

    int signalKilled = 0;
    if (exitStatus >= 128 && !timeoutExceed) {
      signalKilled = exitStatus - 128;
    }

    String stdoutFilePath = '${runsDir.path}/$testBaseName.stdout';
    final stdoutFile = io.File(stdoutFilePath);
    final stderrFile = io.File('${runsDir.path}/$testBaseName.stderr');
    stdoutFile.writeAsBytesSync(stdout);
    stderrFile.writeAsBytesSync(stderr);
    String resultCheckerMessage = '';

    bool checkAnswer = signalKilled==0 && !timeoutExceed;
    int valgrindErrors = 0;
    String valgrindOutput = '';
    SolutionStatus solutionStatus = SolutionStatus.OK;

    final maxDataSizeToShow = 50 * 1024;

    String screenBadSymbols(String s) {
      String result = '';
      int outLength = s.length;
      if (outLength > maxDataSizeToShow) {
        outLength = maxDataSizeToShow;
      }
      for (int i=0; i<outLength; i++) {
        final symbol = s[i];
        int code = symbol.codeUnitAt(0);
        if (code < 32 && code != 10 || code == 0xFF) {
          result += r'\' + code.toString();
        }
        else {
          result += symbol;
        }
      }
      return result;
    }

    if (signalKilled==0 && !timeoutExceed && checkValgrindErrors) {
      log.fine('submission ${submission.id} exited with status $exitStatus on test $testBaseName, checking for valgrind errors');
      String runsPath = '${runner.submissionPrivateDirectory(submission)}/runs';
      final valgrindOut = io.File('$runsPath/valgrind/$testBaseName.valgrind').readAsStringSync();
      valgrindErrors = 0;
      final rxErrorsSummary = RegExp(r'==\d+== ERROR SUMMARY: (\d+) errors');
      final matchEntries = List<RegExpMatch>.from(rxErrorsSummary.allMatches(valgrindOut));
      if (matchEntries.isNotEmpty) {
        RegExpMatch match = matchEntries.first;
        String matchGroup = match.group(1)!;
        valgrindErrors = int.parse(matchGroup);
      }
      if (valgrindErrors > 0) {
        log.fine('submission ${submission.id} has $valgrindErrors valgrind errors on test $testBaseName');
        valgrindOutput = valgrindOut;
        solutionStatus = SolutionStatus.VALGRIND_ERRORS;
        checkAnswer = false;
      }
    }
    if (signalKilled==0 && !timeoutExceed && checkSanitizersErrors) {
      log.fine('submission ${submission.id} exited with status $exitStatus on test $testBaseName, checking for sanitizer errors');
      String errOut = screenBadSymbols(utf8.decode(stderr, allowMalformed: true));
      final errLines = errOut.split('\n');
      List<String> patternParts = [];
      for (final solutionFile in submission.solutionFiles.files) {
        String part = solutionFile.name.replaceAll('.', r'\.');
        patternParts.add(part);
      }
      // final rxRuntimeError = RegExp('('+patternParts.join('|')+r'):\d+:\d+:\s+runtime\s+error:');
      final rxRuntimeError = RegExp(r'==\d+==ERROR:\s+.+Sanitizer:');
      for (final line in errLines) {
        final match = rxRuntimeError.matchAsPrefix(line);
        if (match != null) {
          checkAnswer = false;
          solutionStatus = SolutionStatus.RUNTIME_ERROR;
          log.fine('submission ${submission.id} got runtime error: $line');
          break;
        }
      }
    }
    if (signalKilled==0 && !timeoutExceed && exitStatus == 127) {
      String errOut = screenBadSymbols(utf8.decode(stderr, allowMalformed: true));
      if (errOut.contains('yajudge_error:')) {
        checkAnswer = false;
        solutionStatus = SolutionStatus.RUNTIME_ERROR;
        log.fine('submission ${submission.id} got yajudge error');
      }
    }
    if (signalKilled != 0) {
      log.fine('submission ${submission.id} ($description) killed by signal $signalKilled on test $testBaseName');
      exitStatus = 0;
      solutionStatus = SolutionStatus.RUNTIME_ERROR;
      checkAnswer = false;
    }

    if (timeoutExceed) {
      log.fine('submission ${submission.id} ($description) killed by timeout ${limits.realTimeLimitSec} on test $testBaseName');
      solutionStatus = SolutionStatus.TIME_LIMIT;
    }

    if (checkAnswer) {
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
      // Check for checker_options that overrides input files
      final checkerData = problemChecker().trim().split('\n');
      final checkerOpts = checkerData.length > 1? checkerData[1].split(' ') : [];
      for (String opt in checkerOpts) {
        if (opt.startsWith('stdin=')) {
          stdinFilePath = '${runner.submissionProblemDirectory(submission)}/$wd/${opt.substring(6)}';
          final stdinFile = io.File(stdinFilePath);
          stdinData = stdinFile.existsSync()? stdinFile.readAsBytesSync() : [];
        }
        if (opt.startsWith('stdout=')) {
          stdoutFilePath = '${runner.submissionPrivateDirectory(submission)}/$wd/${opt.substring(7)}';
          final stdoutFile = io.File(stdoutFilePath);
          stdout = stdoutFile.existsSync()? stdoutFile.readAsBytesSync() : [];
        }
        if (opt.startsWith('reference=')) {
          referencePath = '${runner.submissionProblemDirectory(submission)}/$wd/${opt.substring(10)}';
          final referenceFile = io.File(referencePath);
          referenceStdout = referenceFile.existsSync()? referenceFile.readAsBytesSync() : [];
        }
      }
      log.fine('submission ${submission.id} ($description) exited with $exitStatus on test $testBaseName');
      resultCheckerMessage = runChecker(arguments,
          stdinData, stdinFilePath,
          stdout, stdoutFilePath,
          referenceStdout, referencePath,
          wd);
      final checkerOutFile = io.File('${runsDir.path}/$testBaseName.checker');
      checkerOutFile.writeAsStringSync(resultCheckerMessage);
    }

    if (resultCheckerMessage.isNotEmpty) {
      String waMessage = '=== Checker output:\n$resultCheckerMessage\n';
      String args = arguments.join(' ');
      waMessage += '=== Arguments: $args\n';
      List<int> stdinBytesToShow = [];
      if (stdinData.length > maxDataSizeToShow) {
        stdinBytesToShow = stdinData.sublist(0, maxDataSizeToShow);
      } else {
        stdinBytesToShow = stdinData;
      }
      String inputDataToShow = '';
      bool inputIsBinary = false;
      try {
        inputDataToShow = utf8.decode(stdinBytesToShow, allowMalformed: false);
      }
      catch (e) {
        if (e is FormatException) {
          inputIsBinary = true;
        }
      }
      if (stdinData.length > maxDataSizeToShow) {
        inputDataToShow += '  \n(input is too big, truncated to $maxDataSizeToShow bytes)\n';
      }
      else if (inputIsBinary) {
        inputDataToShow = '(input is binary file)\n';
      }
      if (inputDataToShow.isNotEmpty) {
        waMessage += '=== Input data: $inputDataToShow';
      }
      resultCheckerMessage = waMessage;
      solutionStatus = SolutionStatus.WRONG_ANSWER;
    }

    return TestResult(
      testNumber: testNumber,
      target: runsDirPrefix,
      exitStatus: exitStatus,
      status: solutionStatus,
      stderr: screenBadSymbols(utf8.decode(stderr, allowMalformed: true)),
      stdout: screenBadSymbols(utf8.decode(stdout, allowMalformed: true)),
      killedByTimer: timeoutExceed,
      standardMatch: resultCheckerMessage.isEmpty,
      checkerOutput: screenBadSymbols(resultCheckerMessage),
      signalKilled: signalKilled,
      valgrindErrors: valgrindErrors,
      valgrindOutput: screenBadSymbols(valgrindOutput),
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
        path.absolute('${runner.submissionPrivateDirectory(submission)}/$wd')
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
      String solutionPath = '${runner.submissionProblemDirectory(submission)}/build';
      String checkerPy = path.normalize(
          path.absolute('$solutionPath/$checkerName')
      );
      checker = PythonChecker(checkerPy: checkerPy, locationProperties: locationProperties);
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
