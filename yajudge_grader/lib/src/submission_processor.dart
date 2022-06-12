// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:protobuf/protobuf.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'assets_loader.dart';
import 'builders.dart';
import 'checkers.dart';
import 'grader_extra_configs.dart';
import 'abstract_runner.dart';
import 'package:yaml/yaml.dart';

import 'interactors.dart';
import 'runtimes.dart';

class SubmissionProcessor {
  Submission submission;
  final AbstractRunner runner;
  final Logger log = Logger('SubmissionProcessor');
  final GraderLocationProperties locationProperties;
  final GradingLimits defaultLimits;
  final DefaultBuildProperties defaultBuildProperties;
  final DefaultRuntimeProperties defaultRuntimeProperties;
  final SecurityContext defaultSecurityContext;
  late final InteractorFactory interactorFactory;
  late final BuilderFactory builderFactory;
  late final RuntimeFactory runtimeFactory;

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
    required this.defaultBuildProperties,
    required this.defaultRuntimeProperties,
    required this.defaultSecurityContext,
  }) {
    interactorFactory = InteractorFactory(
        locationProperties: locationProperties
    );
    builderFactory = BuilderFactory(
        defaultBuildProperties, runner
    );
    runtimeFactory = RuntimeFactory(
        defaultRuntimeProperties: defaultRuntimeProperties,
        runner: runner,
        interactorFactory: interactorFactory
    );
  }

  Future<void> _processSubmissionGuarded() async {
    runner.createDirectoryForSubmission(submission);

    final gradingOptions = GradingOptionsExtension.loadFromPlainFiles(
      submissionOptionsDirectory
    );

    final builder = builderFactory.createBuilder(submission, gradingOptions);
    assert (builder.canBuild(submission));

    if (builder.canCheckCodeStyle(submission)) {
      final checkStyleResult = await builder.checkStyle(
        submission: submission,
        buildDirRelativePath: '/build',
      );
      final failedFiles = checkStyleResult.where((element) => !element.acceptable);
      if (failedFiles.isNotEmpty) {
        String errorMessage = '';
        for (final checkResult in failedFiles) {
          errorMessage += '${checkResult.fileName}:\n${checkResult.message}\n\n';
        }
        errorMessage = errorMessage.trim();
        submission.styleErrorLog = errorMessage;
        submission.status = SolutionStatus.STYLE_CHECK_ERROR;
        return;
      }
    }

    final extraBuildProperties = TargetProperties(
        properties: gradingOptions.buildProperties
    );
    ExecutableTarget executableTargetToBuild = gradingOptions.executableTarget;
    if (executableTargetToBuild==ExecutableTarget.AutodetectExecutable) {
      executableTargetToBuild = builder.defaultBuildTarget;
    }

    Iterable<BuildArtifact> buildArtifacts = [];

    try {
      buildArtifacts = await builder.build(
        submission: submission,
        buildDirRelativePath: '/build',
        extraBuildProperties: extraBuildProperties,
        target: executableTargetToBuild,
      );
    }
    catch (error) {
      if (error is BuildError) {
        submission.buildErrorLog = error.buildMessage;
        submission.status = SolutionStatus.COMPILATION_ERROR;
        return;
      }
      else {
        rethrow;
      }
    }

    if (buildArtifacts.isEmpty) {
      throw Exception('Nothing to run in this submission');
    }

    await processSolutionArtifacts(buildArtifacts);
    bool hasRuntimeError = submission.testResults.any((e) => e.status==SolutionStatus.RUNTIME_ERROR);
    bool hasValgrindError = submission.testResults.any((e) => e.status==SolutionStatus.VALGRIND_ERRORS);
    bool hasTimeLimit = submission.testResults.any((e) => e.status==SolutionStatus.TIME_LIMIT);
    bool hasWrongAnswer = submission.testResults.any((e) => e.status==SolutionStatus.WRONG_ANSWER);
    if (hasRuntimeError) {
      submission.status = SolutionStatus.RUNTIME_ERROR;
    }
    else if (hasValgrindError) {
      submission.status = SolutionStatus.VALGRIND_ERRORS;
    }
    else if (hasTimeLimit) {
      submission.status = SolutionStatus.TIME_LIMIT;
    }
    else if (hasWrongAnswer) {
      submission.status = SolutionStatus.WRONG_ANSWER;
    }
    else {
      submission.status = SolutionStatus.OK;
    }
  }

  Future<void> processSubmission() async {
    submission = submission.deepCopy();
    try {
      log.info('started processing ${submission.id}');
      await _processSubmissionGuarded();
      log.info('submission ${submission.id} done with status ${submission.status.value} (${submission.status.name})');
    }
    catch (error) {
      submission.status = SolutionStatus.CHECK_FAILED;
      String message = error.toString();
      if (error is Error) {
        String stackTrace = error.stackTrace!=null? error.stackTrace!.toString() : '';
        if (stackTrace.isNotEmpty) {
          message += '\n$stackTrace';
        }
      }
      log.info('submission ${submission.id} failed: $message');
      submission.buildErrorLog = message;
    }
    finally {
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

  Future<void> processSolutionArtifacts(Iterable<BuildArtifact> buildArtifacts) async {
    List<TestResult> testResults = [];
    final gradingOptions = GradingOptionsExtension.loadFromPlainFiles(
        submissionOptionsDirectory
    );
    for (final artifact in buildArtifacts) {
      final gradingLimits = defaultLimits.mergedWith(gradingOptions.limits);
      final runtime = runtimeFactory.createRuntime(
        gradingOptions: gradingOptions,
        gradingLimits: gradingLimits,
        submission: submission,
        artifact: artifact,
      );
      final testsCount = prepareSubmissionTests(runtime.runtimeName);
      for (int testNumber=1; testNumber<=testsCount; testNumber++) {
        final testBaseName = generateTestBaseName(testNumber);
        final runTestArtifact = await runtime.runTargetOnTest(testBaseName);
        final runTestResult = runTestArtifact.toTestResult();
        runTestResult.testNumber = testNumber;
        runTestResult.target = runtime.runtimeName;
        bool checkAnswer = runTestResult.status==SolutionStatus.ANY_STATUS_OR_NULL;
        if (checkAnswer) {
          final checkedTestResult = await processCheckAnswer(testBaseName, runTestResult);
          testResults.add(checkedTestResult);
        }
        else {
          testResults.add(runTestResult);
        }
      }
    }
    submission.testResults.addAll(testResults);
  }

  Future<TestResult> processCheckAnswer(String testBaseName, TestResult testResult) async {
    final testsPath = '${runner.submissionProblemDirectory(submission)}/tests';
    final runsDir = io.Directory(
      '${runner.submissionPrivateDirectory(submission)}/runs/${testResult.target}/'
    );
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
    List<int> stdinData = [];
    final problemStdinFile = io.File('$testsPath/$testBaseName.dat');
    final targetStdinFile = io.File('${runsDir.path}/$testBaseName.dat');
    String stdinFilePath = '';
    String wd;
    if (io.Directory('${runsDir.path}/$testBaseName.dir').existsSync()) {
      wd = '/runs/${testResult.target}/$testBaseName.dir';
    }
    else {
      wd = '/runs/${testResult.target}';
    }
    if (targetStdinFile.existsSync()) {
      stdinData = targetStdinFile.readAsBytesSync();
      stdinFilePath = targetStdinFile.path;
    }
    else if (problemStdinFile.existsSync()) {
      stdinData = problemStdinFile.readAsBytesSync();
      stdinFilePath = problemStdinFile.path;
    }
    String stdoutFilePath = '${runsDir.path}/$testBaseName.stdout';
    for (String opt in checkerOpts) {
      if (opt.startsWith('stdin=')) {
        stdinFilePath = '${runner.submissionProblemDirectory(submission)}/$wd/${opt.substring(6)}';
        final stdinFile = io.File(stdinFilePath);
        stdinData = stdinFile.existsSync()? stdinFile.readAsBytesSync() : [];
      }
      if (opt.startsWith('stdout=')) {
        stdoutFilePath = '${runner.submissionPrivateDirectory(submission)}/$wd/${opt.substring(7)}';
      }
      if (opt.startsWith('reference=')) {
        referencePath = '${runner.submissionProblemDirectory(submission)}/$wd/${opt.substring(10)}';
        final referenceFile = io.File(referencePath);
        referenceStdout = referenceFile.existsSync()? referenceFile.readAsBytesSync() : [];
      }
    }
    final stdoutFile = io.File(stdoutFilePath);
    int outFileMode = 0;
    bool outputIsReadableByOwner = false;
    bool outputIsExecutable = false;
    if (stdoutFile.existsSync()) {
      outFileMode = stdoutFile.statSync().mode;
      final fileAccessMask = int.parse('777', radix: 8);
      final fileAccessMode = outFileMode & fileAccessMask;
      final executableMask = int.parse('111', radix: 8);
      final ownerReadableMask = int.parse('400', radix: 8);
      outputIsReadableByOwner = (fileAccessMode & ownerReadableMask) != 0;
      outputIsExecutable = (fileAccessMode & executableMask) != 0;
    }
    String resultCheckerMessage = '';
    String printableMode = (outFileMode).toRadixString(8);
    if (printableMode.length > 3) {
      printableMode = printableMode.substring(printableMode.length-3);
    }
    printableMode = printableMode.padLeft(4, '0');
    List<int> stdout = [];
    if (!stdoutFile.existsSync()) {
      resultCheckerMessage = 'Output file not exists';
    }
    else if (!outputIsReadableByOwner) {
      resultCheckerMessage = 'Output file has mode $printableMode which not readable by owner';
    }
    else if (outputIsExecutable) {
      resultCheckerMessage = 'Output file has mode $printableMode and it is not secure';
    }
    else {
      stdout = stdoutFile.existsSync()? stdoutFile.readAsBytesSync() : [];
      resultCheckerMessage = runChecker(
          [], // TODO ???
          stdinData, stdinFilePath,
          stdout, stdoutFilePath,
          referenceStdout, referencePath,
          wd
      );
    }

    final checkerOutFile = io.File('${runsDir.path}/$testBaseName.checker');
    checkerOutFile.writeAsStringSync(resultCheckerMessage);

    if (resultCheckerMessage.isNotEmpty) {
      String checkerMessageToShow;
      if (resultCheckerMessage.length > RunTestArtifact.maxDataSizeToShow) {
        checkerMessageToShow = RunTestArtifact.screenBadSymbols(
            resultCheckerMessage.substring(0, RunTestArtifact.maxDataSizeToShow)
        );
      }
      else {
        checkerMessageToShow = RunTestArtifact.screenBadSymbols(resultCheckerMessage);
      }
      String waMessage = '=== Checker output:\n';
      if (resultCheckerMessage.length > RunTestArtifact.maxDataSizeToShow) {
        waMessage += '(truncated to ${RunTestArtifact.maxDataSizeToShow} symbols)\n';
      }
      waMessage += '$checkerMessageToShow\n';
      List<int> stdinBytesToShow = [];
      if (stdinData.length > RunTestArtifact.maxDataSizeToShow) {
        stdinBytesToShow = stdinData.sublist(0, RunTestArtifact.maxDataSizeToShow);
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
      if (stdinData.length > RunTestArtifact.maxDataSizeToShow) {
        inputDataToShow += '  \n(input is too big, truncated to ${RunTestArtifact.maxDataSizeToShow} bytes)\n';
      }
      else if (inputIsBinary) {
        inputDataToShow = '(input is binary file)\n';
      }
      if (inputDataToShow.isNotEmpty) {
        waMessage += '=== Input data: ${RunTestArtifact.screenBadSymbols(inputDataToShow)}';
      }
      testResult.checkerOutput = waMessage;
      testResult.status = SolutionStatus.WRONG_ANSWER;
    }
    else {
      testResult.status = SolutionStatus.OK;
    }
    return testResult;
  }

  static String generateTestBaseName(int number) {
    String baseName = '$number';
    if (number < 10) {
      baseName = '0$baseName';
    }
    if (number < 100) {
      baseName = '0$baseName';
    }
    return baseName;
  }

  io.Directory get submissionOptionsDirectory {
    final cacheDir = locationProperties.cacheDir;
    final dataId = submission.course.dataId;
    final problemSubdir = submission.problemId.replaceAll(':', '/');
    final path = '$cacheDir/$dataId/$problemSubdir/build';
    return io.Directory(path);
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
