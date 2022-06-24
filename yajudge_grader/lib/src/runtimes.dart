import 'dart:async';
import 'dart:convert';

import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:protobuf/protobuf.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'dart:io' as io;
import 'abstract_runner.dart';
import 'builders.dart';
import 'grader_extra_configs.dart';
import 'interactors.dart';
import 'simple_runner.dart';

class RuntimeLaunchError extends Error {
  final String message;

  RuntimeLaunchError(this.message) : super();
}

abstract class DetectedError extends Error {
  String get message;
}

abstract class DetectedRuntimeError extends DetectedError {
}

class ValgrindError extends DetectedRuntimeError {
  final String output;
  final int errorsCount;
  ValgrindError(this.output, this.errorsCount);
  @override
  String get message => output;
}

class SanitizerError extends DetectedRuntimeError {
  final List<String> outputLines;
  SanitizerError(this.outputLines);
  @override
  String get message => 'Sanitizer errors:\n${outputLines.join('\n')}';
}

class JavaRuntimeError extends DetectedRuntimeError {
  final String lastExceptionMessage;
  JavaRuntimeError(this.lastExceptionMessage);
  @override
  String get message => lastExceptionMessage;
}

class RunTestArtifact {
  final List<int> stdout;
  final List<int> stderr;
  final int signalKilled;
  final int exitStatus;
  final bool timeoutExceed;
  DetectedError? detectedError;

  static const maxDataSizeToShow = 50 * 1024;

  RunTestArtifact({
    required this.stdout,
    required this.stderr,
    required this.signalKilled,
    required this.exitStatus,
    required this.timeoutExceed,
    this.detectedError
  });

  String get stdoutAsString => decodeResult(stdout);
  String get stderrAsString => decodeResult(stderr);

  static String decodeResult(List<int> input) {
    return screenBadSymbols(utf8.decode(input, allowMalformed: true));
  }

  static String screenBadSymbols(String s) {
    String result = '';
    int outLength = s.length;
    if (outLength > maxDataSizeToShow) {
      outLength = maxDataSizeToShow;
    }
    for (int i=0; i<outLength; i++) {
      final symbol = s[i];
      int code = symbol.codeUnitAt(0);
      if (code < 32 && code != 10 && code != 9 || code == 0xFF) {
        result += r'\' + code.toString();
      }
      else {
        result += symbol;
      }
    }
    return result;
  }

  TestResult toTestResult() {
    SolutionStatus status = SolutionStatus.OK;
    String stdoutResult = stdoutAsString;
    String stderrResult = stderrAsString;
    if (signalKilled > 0) {
      stderrResult = _removeYajudgeInternals(stderrResult);
    }
    int valgrindErrorsCount = 0;
    String valgrindOutput = '';
    if (signalKilled != 0) {
      status = SolutionStatus.RUNTIME_ERROR;
    }
    if (detectedError is ValgrindError) {
      status = SolutionStatus.VALGRIND_ERRORS;
      valgrindErrorsCount = (detectedError as ValgrindError).errorsCount;
      valgrindOutput = (detectedError as ValgrindError).output;
    }
    else if (detectedError is DetectedRuntimeError) {
      status = SolutionStatus.RUNTIME_ERROR;
    }
    if (timeoutExceed) {
      status = SolutionStatus.TIME_LIMIT;
    }
    return TestResult(
      exitStatus: exitStatus,
      status: status,
      stdout: stdoutResult,
      stderr: stderrResult,
      killedByTimer: timeoutExceed,
      signalKilled: signalKilled,
      valgrindErrors: valgrindErrorsCount,
      valgrindOutput: screenBadSymbols(valgrindOutput),
    ).deepCopy();
  }

  static String _removeYajudgeInternals(String src) {
    List<String> lines = src.split('\n');
    final rxYajudgeInternalScript = RegExp(r'run_wrapper_stage\d\d\.sh');
    lines = lines.where((element) => !rxYajudgeInternalScript.hasMatch(element)).toList();
    return lines.join('\n');
  }

}


abstract class AbstractRuntime {
  final String targetName;
  final TargetProperties runtimeProperties;
  final AbstractRunner runner;
  final Submission submission;
  final BuildArtifact artifact;
  final String runtimeName;
  GradingLimits gradingLimits;
  late final String coprocessFileName;
  final log = Logger('Runtime');
  final AbstractInteractor? interactor;

  AbstractRuntime({
    required this.runtimeProperties,
    required this.runner,
    required this.submission,
    required this.runtimeName,
    required this.gradingLimits,
    required String coprocessFileName,
    required this.artifact,
    required this.interactor,
    required this.targetName,
  }) {
    gradingLimits = gradingLimits.deepCopy();
    final extraMemoryLimit = runtimeProperties.properties['extra_memory_limit'];
    final cpuTimeScale = runtimeProperties.properties['cpu_time_scale'];
    if (extraMemoryLimit!=null && gradingLimits.memoryMaxLimitMb!=0) {
      int oldLimit = gradingLimits.memoryMaxLimitMb.toInt();
      int extra = int.parse(extraMemoryLimit);
      int newLimit = oldLimit + extra;
      gradingLimits.memoryMaxLimitMb = Int64(newLimit);
    }
    if (cpuTimeScale!=null) {
      int oldLimit = gradingLimits.cpuTimeLimitSec.toInt();
      double scale = double.parse(cpuTimeScale);
      int newLimit = (oldLimit * scale).floor();
      gradingLimits.cpuTimeLimitSec = Int64(newLimit);
    }
    if (coprocessFileName.isNotEmpty && !coprocessFileName.startsWith('/')) {
      this.coprocessFileName = '/build/$coprocessFileName';
    }
    else {
      this.coprocessFileName = coprocessFileName;
    }
  }

  Future<YajudgeProcess> startSolutionProcess({
    required String workDir,
    required List<String> arguments,
    required String testBaseName,
  });

  RunTestArtifact postProcessArtifact(RunTestArtifact artifact, String testBaseName);

  Future<RunTestArtifact> runTargetOnTest(String testBaseName) async {
    log.info('running test $testBaseName ($runtimeName) for submission ${submission.id}');

    final runsDir = io.Directory('${runner.submissionPrivateDirectory(submission)}/runs/$runtimeName/');
    String workDir;
    if (io.Directory('${runsDir.path}/$testBaseName.dir').existsSync()) {
      workDir = '/runs/$runtimeName/$testBaseName.dir';
    }
    else {
      workDir = '/runs/$runtimeName';
    }

    final arguments = _testRunArguments(testBaseName);
    final stdinData = _testStdinData(testBaseName);

    Function? interactorShutdown;
    final solutionProcess = await startSolutionProcess(
      workDir: workDir,
      arguments: arguments,
      testBaseName: testBaseName
    );

    if (interactor != null) {
      interactorShutdown = await interactor!.interact(
          solutionProcess, workDir, stdinData.name
      );
    }
    else {
      if (stdinData.data.isNotEmpty) {
        await solutionProcess.writeToStdin(stdinData.data);
      }
      await solutionProcess.closeStdin();
    }

    bool timeoutExceed = false;
    Timer? timer;

    void handleTimeout() {
      timeoutExceed = true;
      runner.killProcess(solutionProcess);
    }

    if (gradingLimits.realTimeLimitSec > 0) {
      final timerDuration = Duration(
          seconds: gradingLimits.realTimeLimitSec.toInt()
      );
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

    final stdoutFilePath = '${runsDir.path}/$testBaseName.stdout';
    final stdoutFile = io.File(stdoutFilePath);
    final stderrFile = io.File('${runsDir.path}/$testBaseName.stderr');
    stdoutFile.writeAsBytesSync(stdout);
    stderrFile.writeAsBytesSync(stderr);

    return postProcessArtifact(RunTestArtifact(
      stdout: stdout,
      stderr: stderr,
      signalKilled: signalKilled,
      exitStatus: exitStatus,
      timeoutExceed: timeoutExceed,
    ), testBaseName);

  }

  io.Directory get _testsDirectory {
    final problemDirectoryPath = runner.submissionProblemDirectory(submission);
    final testsPath = '$problemDirectoryPath/tests';
    return io.Directory(testsPath);
  }

  io.Directory get _runsDirectory {
    final submissionDirectoryPath = runner.submissionPrivateDirectory(submission);
    final runsPath = '$submissionDirectoryPath/runs/$runtimeName';
    return io.Directory(runsPath);
  }

  List<String> _testRunArguments(String testBaseName) {
    final testsDir = _testsDirectory;
    final runsDir = _runsDirectory;
    List<String> arguments = [];
    final problemArgsFile = io.File('${testsDir.path}/$testBaseName.args');
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
    arguments = _parseTestInfArgumentsLine(argumentsLine);
    return arguments;
  }

  List<String> _parseTestInfArgumentsLine(String line) {
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

  File _testStdinData(String testBaseName) {
    final testsDir = _testsDirectory;
    final runsDir = _runsDirectory;
    List<int> stdinData = [];
    final problemStdinFile = io.File('${testsDir.path}/$testBaseName.dat');
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

    return File(name: stdinFilePath, data: stdinData);
  }

}

class NativeRuntime extends AbstractRuntime {
  NativeRuntime({
    required super.runtimeProperties,
    required super.runner,
    required super.submission,
    required super.artifact,
    required super.gradingLimits,
    required super.coprocessFileName,
    required super.interactor,
    required super.targetName,
  }) : super(runtimeName: 'native');

  @override
  RunTestArtifact postProcessArtifact(RunTestArtifact artifact, String testBaseName) {
    if (artifact.signalKilled!=0 || artifact.timeoutExceed) {
      return artifact; // do not post process crashed run
    }
    final errLines = artifact.stderrAsString.split('\n');
    final rxRuntimeError = RegExp(r'==\d+==ERROR:\s+.+Sanitizer:');
    List<String> errorLines = [];
    for (final line in errLines) {
      final match = rxRuntimeError.matchAsPrefix(line);
      if (match != null) {
        errorLines.add(line);
      }
    }
    if (errorLines.isNotEmpty) {
      artifact.detectedError = SanitizerError(errorLines);
    }
    return artifact;
  }

  @override
  Future<YajudgeProcess> startSolutionProcess({
    required String workDir,
    required List<String> arguments,
    required String testBaseName,
  }) {
    assert(artifact.fileNames.length == 1);
    return runner.start(
      submission,
      [artifact.fileNames.single] + arguments,
      workingDirectory: workDir,
      limits: gradingLimits,
      coprocessFileName: coprocessFileName,
      targetName: targetName,
    );
  }
}

class ValgrindRuntime extends AbstractRuntime {
  ValgrindRuntime({
    required super.runtimeProperties,
    required super.runner,
    required super.submission,
    required super.gradingLimits,
    required super.coprocessFileName,
    required super.artifact,
    required super.interactor,
    required super.targetName,
  }) : super(runtimeName: 'valgrind');

  @override
  RunTestArtifact postProcessArtifact(RunTestArtifact artifact, String testBaseName) {
    if (artifact.signalKilled!=0 || artifact.timeoutExceed) {
      return artifact; // do not post process crashed run
    }
    final valgrindOutPath = '${_runsDirectory.path}/$testBaseName.valgrind';
    final valgrindOut = io.File(valgrindOutPath).readAsStringSync();
    int valgrindErrors = 0;
    final rxErrorsSummary = RegExp(r'==\d+== ERROR SUMMARY: (\d+) errors');
    final matchEntries = List<RegExpMatch>.from(rxErrorsSummary.allMatches(valgrindOut));
    if (matchEntries.isNotEmpty) {
      RegExpMatch match = matchEntries.first;
      String matchGroup = match.group(1)!;
      valgrindErrors = int.parse(matchGroup);
    }
    if (valgrindErrors > 0) {
      artifact.detectedError = ValgrindError(valgrindOut, valgrindErrors);
    }
    return artifact;
  }

  @override
  Future<YajudgeProcess> startSolutionProcess({
    required String workDir,
    required List<String> arguments,
    required String testBaseName,
  }) {
    assert(artifact.fileNames.length == 1);
    String valgrindExecutable = runtimeProperties.executable;
    if (valgrindExecutable.isEmpty) {
      valgrindExecutable = 'valgrind';
    }
    List<String> valgrindOptions = runtimeProperties.property('runtime_options');
    valgrindOptions.insert(0, '--tool=memcheck');
    final logFileName = '/runs/$runtimeName/$testBaseName.valgrind';
    final logOption = '--log-file=$logFileName';
    valgrindOptions.add(logOption);
    return runner.start(
      submission,
      [valgrindExecutable] + valgrindOptions + [artifact.fileNames.single] + arguments,
      workingDirectory: workDir,
      limits: gradingLimits,
      coprocessFileName: coprocessFileName,
      targetName: targetName,
    );
  }
}

class JavaRuntime extends AbstractRuntime {
  JavaRuntime({
    required super.runtimeProperties,
    required super.runner,
    required super.submission,
    required super.gradingLimits,
    required super.coprocessFileName,
    required super.artifact,
    required super.interactor,
    required super.targetName,
  }) : super(runtimeName: 'java');

  @override
  RunTestArtifact postProcessArtifact(RunTestArtifact artifact, String testBaseName) {
    if (artifact.exitStatus == 1) {
      // Parse java runtime error
      final errorText = utf8.decode(artifact.stderr, allowMalformed: true);
      final rxJavaException = RegExp(r'Exception in thread "(.+)" (.+):');
      final matches = rxJavaException.allMatches(errorText).toList();
      if (matches.isNotEmpty) {
        final lastMatch = matches.last;
        final errorStart = lastMatch.start;
        final exceptionMessage = errorText.substring(errorStart);
        artifact.detectedError = JavaRuntimeError(exceptionMessage);
      }
    }
    return artifact;
  }

  @override
  Future<YajudgeProcess> startSolutionProcess({required String workDir, required List<String> arguments, required String testBaseName}) {
    String javaExecutable = runtimeProperties.executable;
    if (javaExecutable.isEmpty) {
      javaExecutable = 'java';
    }
    List<String> javaOptions = runtimeProperties.property('runtime_options');
    if (gradingLimits.stackSizeLimitMb > 0) {
      javaOptions.add('-Xss${gradingLimits.stackSizeLimitMb}m');
    }
    if (gradingLimits.memoryMaxLimitMb > 0) {
      javaOptions.add('-Xmx${gradingLimits.memoryMaxLimitMb}m');
    }
    List<String> entryPoint = [];
    if (artifact.executableTarget == ExecutableTarget.JavaClass) {
      String fileName = '';
      String mainClass = '';
      if (runtimeProperties.property('main_class').length == 1) {
        mainClass = runtimeProperties.property('main_class').single;
      }
      else if (artifact.fileNames.length == 1) {
        fileName = artifact.fileNames.single;
        if (fileName.startsWith('/build/')) {
          fileName = fileName.substring('/build/'.length);
        }
        String className = fileName.replaceAll('/', '.');
        if (className.endsWith('.class')) {
          className = className.substring(0, className.length-6);
        }
        mainClass = className;
      }
      else {
        throw RuntimeLaunchError('no main class specified');
      }
      String classPath = '/build';
      if (runner is SimpleRunner) {
        classPath = runner.submissionPrivateDirectory(submission) + classPath;
      }
      entryPoint = ['-classpath', classPath, mainClass];
    }
    else if (artifact.executableTarget == ExecutableTarget.JavaJar) {
      assert(artifact.fileNames.length == 1);
      String fileName = artifact.fileNames.single;
      if (fileName.startsWith('/build/')) {
        fileName = fileName.substring('/build/'.length);
      }
      entryPoint = ['-jar', fileName];
    }
    final jreLimits = gradingLimits.deepCopy();
    jreLimits.stackSizeLimitMb = Int64(0);
    jreLimits.memoryMaxLimitMb = Int64(0);
    jreLimits.procCountLimit = Int64(0);
    jreLimits.fdCountLimit = Int64(0);
    return runner.start(
      submission,
      [javaExecutable] + javaOptions + entryPoint + arguments,
      workingDirectory: workDir,
      limits: jreLimits,
      coprocessFileName: coprocessFileName,
      runTargetIsScript: true,
      targetName: targetName,
    );
  }
}

abstract class InterpreterRuntime extends AbstractRuntime {
  late final String interpreterExecutable;

  InterpreterRuntime({
    required super.runtimeProperties,
    required super.runner,
    required super.submission,
    required super.runtimeName,
    required super.gradingLimits,
    required super.coprocessFileName,
    required super.artifact,
    required super.interactor,
    required super.targetName,
  });

  @override
  Future<YajudgeProcess> startSolutionProcess({
    required String workDir,
    required List<String> arguments,
    required String testBaseName
  }) {
    List<String> interpreterOptions = runtimeProperties.property('runtime_options');
    String fileName = '';
    if (artifact.fileNames.length == 1) {
      fileName = artifact.fileNames.single;
    }
    else {
      final mainValue = runtimeProperties.property('main-file');
      if (mainValue.length != 1) {
        throw ArgumentError('wrong main file property', 'main_file');
      }
      fileName = mainValue.single;
    }
    return runner.start(
      submission,
      [interpreterExecutable] + interpreterOptions + [fileName] + arguments,
      workingDirectory: workDir,
      limits: gradingLimits,
      coprocessFileName: coprocessFileName,
      runTargetIsScript: false,
      targetName: targetName,
    );
  }
}

class ShellRuntime extends InterpreterRuntime {
  ShellRuntime({
    required super.runtimeProperties,
    required super.runner,
    required super.submission,
    required super.gradingLimits,
    required super.coprocessFileName,
    required super.artifact,
    required super.interactor,
    required super.targetName,
  }) : super(runtimeName: 'shell') {
    String executable = runtimeProperties.executable;
    if (executable.isEmpty) {
      executable = 'bash';
    }
    super.interpreterExecutable = executable;
  }

  @override
  RunTestArtifact postProcessArtifact(RunTestArtifact artifact, String testBaseName) {
    return artifact;
  }

}


class RuntimeFactory {
  final DefaultRuntimeProperties defaultRuntimeProperties;
  final AbstractRunner runner;
  final InteractorFactory interactorFactory;

  RuntimeFactory({
    required this.defaultRuntimeProperties,
    required this.runner,
    required this.interactorFactory
  });

  AbstractRuntime createRuntime({
    required GradingOptions gradingOptions,
    required GradingLimits gradingLimits,
    required Submission submission,
    required BuildArtifact artifact,
  }) {
    final target = artifact.executableTarget;
    final extraRuntimeProperties = TargetProperties(
        properties: gradingOptions.targetProperties
    );
    final runtimeProperties = defaultRuntimeProperties
        .propertiesForRuntime(target).mergeWith(extraRuntimeProperties);
    final coprocessFileName = gradingOptions.coprocess.name;
    final interactorName = gradingOptions.interactor.name;
    AbstractInteractor? interactor;
    if (interactorName.isNotEmpty) {
      interactor = interactorFactory.getInteractor(interactorName);
    }
    final targetName = artifact.executableTarget.name;
    final javaRuntime = JavaRuntime(
      runtimeProperties: runtimeProperties,
      runner: runner,
      submission: submission,
      gradingLimits: gradingLimits,
      coprocessFileName: coprocessFileName,
      artifact: artifact,
      interactor: interactor,
      targetName: targetName,
    );
    final nativeRuntime = NativeRuntime(
      runtimeProperties: runtimeProperties,
      runner: runner,
      submission: submission,
      gradingLimits: gradingLimits,
      coprocessFileName: coprocessFileName,
      artifact: artifact,
      interactor: interactor,
      targetName: targetName,
    );
    final valgrindRuntime = ValgrindRuntime(
      runtimeProperties: runtimeProperties,
      runner: runner,
      submission: submission,
      gradingLimits: gradingLimits,
      coprocessFileName: coprocessFileName,
      artifact: artifact,
      interactor: interactor,
      targetName: targetName,
    );
    final shellRuntime = ShellRuntime(
      runtimeProperties: runtimeProperties,
      runner: runner,
      submission: submission,
      gradingLimits: gradingLimits,
      coprocessFileName: coprocessFileName,
      artifact: artifact, interactor: interactor,
      targetName: targetName,
    );
    switch (target) {
      case ExecutableTarget.ShellScript:
        return shellRuntime;
      case ExecutableTarget.JavaClass:
      case ExecutableTarget.JavaJar:
        return javaRuntime;
      case ExecutableTarget.Native:
      case ExecutableTarget.NativeWithSanitizers:
        return nativeRuntime;
      case ExecutableTarget.NativeWithValgrind:
        return valgrindRuntime;
      case ExecutableTarget.PythonScript:
        throw UnimplementedError('python support not implemented yet');
      case ExecutableTarget.QemuSystemImage:
        throw UnimplementedError('qemu-system support not implemented yet');
      default:
        throw UnsupportedError('unknown runtime to create');
    }
  }

}