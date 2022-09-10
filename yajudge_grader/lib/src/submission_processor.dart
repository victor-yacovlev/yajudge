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
import 'package:posix/posix.dart' as posix;

import 'grader_service.dart';
import 'interactors.dart';
import 'runtimes.dart';


class SubmissionProcessor {
  final AbstractRunner runner;
  Logger log = Logger('SubmissionProcessor');
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
    log = Logger('SubmissionProcessor');
  }

  Future<Submission> processSubmissionGuarded(Submission submission) async {

    runner.createDirectoryForSubmission(submission, '');

    final gradingOptions = GradingOptionsExtension.loadFromPlainFiles(
      submissionOptionsDirectory(submission),
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
        return submission;
      }
    }

    Future<BuildResult> futureBuildResult;

    if (!gradingOptions.testsRequiresBuild) {
      futureBuildResult = buildSolution(
        submission: submission,
        builder: builder,
        buildRelativePath: '/build',
        gradingOptions: gradingOptions,
      );
    }
    else {
      final emptyCompleter = Completer<BuildResult>();
      futureBuildResult = emptyCompleter.future;
      emptyCompleter.complete(BuildResult.empty());
    }

    final resultCompleter = Completer<Submission>();

    futureBuildResult.then((buildResult) {
      if (buildResult.isError) {
        resultCompleter.complete(buildResult.applyTo(submission));
      }
      else {
        final artifacts = buildResult.artifacts;
        final testsResults = processTests(
          submission: submission,
          builder: builder,
          buildArtifacts: artifacts,
          gradingOptions: gradingOptions,
        );
        testsResults.then((value) {
          resultCompleter.complete(applyTestResults(submission, value));
        });
      }
    });

    return resultCompleter.future;
  }

  static Submission applyTestResults(Submission submission, List<TestResult> testResults) {
    bool hasCompileError = testResults.any((e) => e.status==SolutionStatus.COMPILATION_ERROR);
    bool hasRuntimeError = testResults.any((e) => e.status==SolutionStatus.RUNTIME_ERROR);
    bool hasValgrindError = testResults.any((e) => e.status==SolutionStatus.VALGRIND_ERRORS);
    bool hasTimeLimit = testResults.any((e) => e.status==SolutionStatus.TIME_LIMIT);
    bool hasWrongAnswer = testResults.any((e) => e.status==SolutionStatus.WRONG_ANSWER);
    if (hasCompileError) {
      submission.status = SolutionStatus.COMPILATION_ERROR;
      submission.buildErrorLog = ''; // test but not submission property
    }
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
    if (!{SolutionStatus.COMPILATION_ERROR, SolutionStatus.CHECK_FAILED}.contains(submission.status)) {
      submission.clearBuildErrorLog();
    }
    return submission..testResults.addAll(testResults);
  }

  Future<BuildResult> buildSolution({
    required Submission submission,
    required AbstractBuilder builder,
    required String buildRelativePath,
    required GradingOptions gradingOptions,
  }) async {
    final extraBuildProperties = TargetProperties(
        properties: gradingOptions.buildProperties
    );
    ExecutableTarget executableTargetToBuild = gradingOptions.executableTarget;
    if (executableTargetToBuild==ExecutableTarget.AutodetectExecutable) {
      executableTargetToBuild = builder.defaultBuildTarget;
    }
    return builder.build(
      submission: submission,
      buildDirRelativePath: buildRelativePath,
      extraBuildProperties: extraBuildProperties,
      target: executableTargetToBuild,
    );
  }

  Future<List<TestResult>> processTests({
    required Submission submission,
    required Iterable<BuildArtifact> buildArtifacts,
    required GradingOptions gradingOptions,
    required AbstractBuilder builder,
  }) async {

    List<TestResult> result = [];
    Map<int,Iterable<BuildArtifact>> testsBuildArtifacts = {};
    int buildTestsCount = 0;
    if (gradingOptions.testsRequiresBuild) {
      // build tests
      buildTestsCount = prepareBuildTests(submission);
      for (int i=1; i<=buildTestsCount; i++) {
        final testBaseName = '$i'.padLeft(3, '0');
        final testBuildSubdir = '/$testBaseName.build';
        final testBuildDir = io.Directory(
          '${runner.submissionPrivateDirectory(submission)}$testBuildSubdir'
        );
        submission.solutionFiles.saveAll(testBuildDir);
        final buildResult = await buildSolution(
          submission: submission,
          builder: builder,
          buildRelativePath: testBuildSubdir,
          gradingOptions: gradingOptions,
        );
        if (!buildResult.isError) {
          testsBuildArtifacts[i] = buildResult.artifacts;
        }
        else {
          testsBuildArtifacts[i] = [];
        }
      }
    }

    // run build artifacts on tests
    if (gradingOptions.testsRequiresBuild) {
      for (int i=0; i<buildTestsCount; i++) {
        final testNumber = i + 1;
        final artifacts = testsBuildArtifacts[testNumber]!;
        result.addAll(
          await processSolutionArtifacts(
            submission,
            artifacts,
            onlyForTestNumber: testNumber
          )
        );
      }
      return result;
    }
    else {
      return processSolutionArtifacts(submission, buildArtifacts);
    }
  }

  Future<Submission> processSubmission(Submission submission) {
    submission = submission.deepCopy();
    log.info('started processing ${submission.id}');
    final futureProcessed = processSubmissionGuarded(submission);
    final resultCompleter = Completer<Submission>();
    futureProcessed.then((processed) {
      log.info('submission ${processed.id} done with status ${processed.status.value} (${processed.status.name})');
      log.info('releasing directory for submission ${processed.id}');
      runner.releaseDirectoryForSubmission(processed, '');
      resultCompleter.complete(processed);
    }, onError: (error) {
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
      log.info('releasing directory for submission ${submission.id}');
      runner.releaseDirectoryForSubmission(submission, '');
      resultCompleter.complete(submission);
    });
    return resultCompleter.future;
  }


  String problemChecker(Submission submission) {
    String solutionPath = '${runner.submissionProblemDirectory(submission)}/build';
    return io.File('$solutionPath/.checker').readAsStringSync().trim();
  }


  int problemTestsCount(Submission submission) {
    String solutionPath = '${runner.submissionProblemDirectory(submission)}/tests';
    return int.parse(io.File('$solutionPath/.tests_count').readAsStringSync().trim());
  }

  String problemTestsGenerator(Submission submission) {
    String solutionPath = '${runner.submissionProblemDirectory(submission)}/build';
    final generatorFile = io.File('$solutionPath/.tests_generator');
    if (generatorFile.existsSync()) {
      return generatorFile.readAsStringSync().trim();
    } else {
      return '';
    }
  }

  int prepareBuildTests(Submission submission) {
    String testsPath = '${runner.submissionProblemDirectory(submission)}/tests';
    final buildsDir = io.Directory('${runner.submissionPrivateDirectory(submission)}/');
    // Unpack -build.tgz bundles if any exists
    int maxBuildTestCount = problemTestsCount(submission);
    int buildTestCount = 0;
    for (int i=1; i<=maxBuildTestCount; i++) {
      String testBaseName = '$i'.padLeft(3, '0');
      final bundleFile = io.File('$testsPath/$testBaseName-build.tgz');
      if (bundleFile.existsSync()) {
        buildTestCount ++;
        io.Process.runSync('tar', ['zxf', bundleFile.path], workingDirectory: buildsDir.path);
      }
      else {
        break;
      }
    }
    return buildTestCount;
  }

  int prepareRuntimeTests(Submission submission, String targetPrefix, {int onlyForTestNumber = 0}) {
    String testsPath = '${runner.submissionProblemDirectory(submission)}/tests';
    final runsDir = io.Directory('${runner.submissionPrivateDirectory(submission)}/runs/$targetPrefix/');

    runsDir.createSync(recursive: true);
    tryChmod(runsDir.absolute.path, '770');

    // Unpack .tgz bundles if any exists
    for (int i=1; i<=problemTestsCount(submission); i++) {
      if (onlyForTestNumber>0 && i!=onlyForTestNumber) {
        continue;
      }
      String testBaseName = '$i'.padLeft(3, '0');
      final bundleFile = io.File('$testsPath/$testBaseName.tgz');
      if (bundleFile.existsSync()) {
        io.Process.runSync('tar', ['zxf', bundleFile.path], workingDirectory: runsDir.path);
      }
    }

    // Generate tests if script provided
    String testsGenerator = problemTestsGenerator(submission);
    if (testsGenerator.isEmpty) {
      return problemTestsCount(submission);
    }
    final testsCountFile = io.File('${runsDir.path}/.tests_count');
    if (testsCountFile.existsSync()) {
      // already generated
      return int.parse(testsCountFile.readAsStringSync().trim());
    }

    if (testsGenerator.endsWith('.py')) {
      final wrappersDir = io.Directory('${locationProperties.cacheDir}/wrappers');
      if (!wrappersDir.existsSync()) {
        wrappersDir.createSync(recursive: true);
        tryChmod(wrappersDir.absolute.path, '770');
      }
      final wrapperFile = io.File('${wrappersDir.path}/tests_generator_wrapper.py');
      if (!wrapperFile.existsSync()) {
        final content = assetsLoader.fileAsBytes('tests_generator_wrapper.py');
        wrapperFile.writeAsBytesSync(content);
        tryChmod(wrapperFile.absolute.path, '660');
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
      return int.parse(testsCountFile.readAsStringSync().trim());
    }
    else {
      throw UnimplementedError('Tests generators other than Python not supported yet: $testsGenerator');
    }
  }

  Future<List<TestResult>> processSolutionArtifacts(
      Submission submission,
      Iterable<BuildArtifact> buildArtifacts,
      {int onlyForTestNumber = 0}
      ) async {
    List<TestResult> testResults = [];
    final gradingOptions = GradingOptionsExtension.loadFromPlainFiles(
        submissionOptionsDirectory(submission)
    );
    for (final artifact in buildArtifacts) {
      final gradingLimits = defaultLimits.mergedWith(gradingOptions.limits);
      final runtime = runtimeFactory.createRuntime(
        gradingOptions: gradingOptions,
        gradingLimits: gradingLimits,
        submission: submission,
        artifact: artifact,
      );
      final testsCount = prepareRuntimeTests(submission, runtime.runtimeName, onlyForTestNumber: onlyForTestNumber);
      for (int testNumber=1; testNumber<=testsCount; testNumber++) {
        if (onlyForTestNumber>0 && onlyForTestNumber!=testNumber) {
          continue;
        }
        log.info('processing test $testNumber using ${artifact.fileNames}');
        final testBaseName = '$testNumber'.padLeft(3, '0');
        final runTestArtifact = await runtime.runTargetOnTest(testBaseName);
        final runTestResult = runTestArtifact.toTestResult();
        log.info('run finished with status ${runTestResult.status.name} (${runTestResult.status.value})');
        runTestResult.testNumber = testNumber;
        runTestResult.target = runtime.runtimeName;
        bool checkAnswer = runTestResult.status==SolutionStatus.OK;
        bool failed = !checkAnswer;
        if (checkAnswer) {
          final checkedTestResult = await processCheckAnswer(submission, runtime, testBaseName, runTestResult);
          failed = checkedTestResult.status!=SolutionStatus.OK;
          testResults.add(checkedTestResult);
        }
        else {
          testResults.add(runTestResult);
        }
        if (failed) {
          return testResults;
        }
      }
    }
    return testResults;
  }

  Future<TestResult> processCheckAnswer(Submission submission, AbstractRuntime runtime, String testBaseName, TestResult testResult) async {
    final testsPath = '${runner.submissionProblemDirectory(submission)}/tests';
    final runsDir = io.Directory(
      '${runner.submissionPrivateDirectory(submission)}/runs/${testResult.target}/'
    );
    List<int> referenceStdout = [];
    List<int> referenceStderr = [];
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
    final problemErrFile = io.File('$testsPath/$testBaseName.err');
    final targetErrFile = io.File('${runsDir.path}/$testBaseName.err');
    String errorReferencePath = '';
    if (targetErrFile.existsSync()) {
      referenceStderr = targetErrFile.readAsBytesSync();
      errorReferencePath = targetErrFile.path;
    }
    else if (problemErrFile.existsSync()) {
      referenceStderr = problemErrFile.readAsBytesSync();
      errorReferencePath = problemErrFile.path;
    }
    // Check for checker_options that overrides input files
    final checkerData = problemChecker(submission).trim().split('\n');
    final checkerOpts = checkerData.length > 1? checkerData[1].split(' ') : [];
    List<int> stdinData = [];
    final problemStdinFile = io.File('$testsPath/$testBaseName.dat');
    final targetStdinFile = io.File('${runsDir.path}/$testBaseName.dat');
    final testRunArguments = runtime.testRunArguments(testBaseName);
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
    String stderrFilePath = '${runsDir.path}/$testBaseName.stderr';
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
        submission,
        testRunArguments.item2, testRunArguments.item1,
        stdinData, stdinFilePath,
        stdout, stdoutFilePath,
        referenceStdout, referencePath,
        wd
      );
    }

    final checkerOutFile = io.File('${runsDir.path}/$testBaseName.checker');
    checkerOutFile.writeAsStringSync(resultCheckerMessage);

    if (resultCheckerMessage.isNotEmpty) {
      testResult.checkerOutput = formatCheckerOutput(
          resultCheckerMessage, 'Checker output', stdinData
      );
      testResult.status = SolutionStatus.WRONG_ANSWER;
    }
    else {
      testResult.status = SolutionStatus.OK;
    }

    final stderrFile = io.File(stderrFilePath);
    if (testResult.status == SolutionStatus.OK && stderrFile.existsSync()) {
      List<int> stderr = stderrFile.readAsBytesSync();
      final textChecker = TextChecker();
      final errCheckerOutput = textChecker.matchData([], [], stderr, referenceStderr, '', '', '');
      if (errCheckerOutput.isNotEmpty) {
        testResult.checkerOutput = formatCheckerOutput(
            errCheckerOutput, 'Checker output on stderr stream', stdinData,
        );
        testResult.status = SolutionStatus.WRONG_ANSWER;
      }
    }
    return testResult;
  }

  static String formatCheckerOutput(String checkerOutput, String title, List<int> stdinData) {
    String checkerMessageToShow;
    if (checkerOutput.length > RunTestArtifact.maxDataSizeToShow) {
      checkerMessageToShow = RunTestArtifact.screenBadSymbols(
          checkerOutput.substring(0, RunTestArtifact.maxDataSizeToShow)
      );
    }
    else {
      checkerMessageToShow = RunTestArtifact.screenBadSymbols(checkerOutput);
    }
    String waMessage = '=== $title:\n';
    if (checkerOutput.length > RunTestArtifact.maxDataSizeToShow) {
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
    return waMessage;
  }

  io.Directory submissionOptionsDirectory(Submission submission) {
    final cacheDir = locationProperties.cacheDir;
    final dataId = submission.course.dataId;
    final problemSubdir = submission.problemId.replaceAll(':', '/');
    final path = '$cacheDir/$dataId/$problemSubdir/build';
    return io.Directory(path);
  }


  String runChecker(
      Submission submission,
      List<String> args, String argsName,
      List<int> stdin, String stdinName,
      List<int> stdout, String stdoutName,
      List<int> reference, String referenceName,
      String wd)
  {
    final checkerData = problemChecker(submission).trim().split('\n');
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
      return checker.matchFiles(argsName, stdinName, stdoutName, referenceName, wd, root, checkerOpts);
    } else {
      return checker.matchData(args, stdin, stdout, reference, wd, root, checkerOpts);
    }
  }


}
