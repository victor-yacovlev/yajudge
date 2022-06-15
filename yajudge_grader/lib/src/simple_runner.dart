import 'dart:async';

import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:path/path.dart' as path;
import 'dart:io' as io;
import 'abstract_runner.dart';

class SimpleRunner extends AbstractRunner {

  final GraderLocationProperties locationProperties;
  final Logger log = Logger('ChrootedRunner');

  SimpleRunner({required this.locationProperties});

  @override
  void createDirectoryForSubmission(Submission submission, String target) {
    String submissionPath = path.absolute(locationProperties.workDir, '${submission.id}');
    String courseId = submission.course.dataId;
    String problemId = submission.problemId;
    String problemContentPath = path.absolute(
        locationProperties.cacheDir, 
        courseId, 
        problemId.replaceAll(':', '/'),
    );
    final submissionFilesDir = io.Directory('$submissionPath/build');
    submissionFilesDir.createSync(recursive: true);
    final problemContent = io.Directory(problemContentPath);
    problemContent.listSync().forEach((element) {
      final copyResult = io.Process.runSync('cp', ['-Rf', element.path, submissionPath]);
      assert(copyResult.exitCode == 0);
    });
    final fileNames = submission.solutionFiles.files.map((e) => e.name);
    io.File('${submissionFilesDir.path}/.solution_files').writeAsStringSync(
        fileNames.join('\n')
    );
    for (final file in submission.solutionFiles.files) {
      String filePath = path.normalize('${submissionFilesDir.path}/${file.name}');
      String fileDir = path.dirname(filePath);
      io.Directory(fileDir).createSync(recursive: true);
      io.File(filePath).writeAsBytesSync(file.data);
    }
  }

  @override
  void releaseDirectoryForSubmission(Submission submission, String target) {
    // Do nothing to keep data for possible debug
  }

  @override
  Future<YajudgeProcess> start(Submission submission, List<String> arguments, {
    required String workingDirectory,
    Map<String, String>? environment,
    GradingLimits? limits,
    bool runTargetIsScript = false,
    String coprocessFileName = '',
    required String targetName,
      }) async
  {
    assert (arguments.isNotEmpty);
    String executable = arguments.first;
    arguments = arguments.sublist(1);
    arguments.removeWhere((element) => element.trim().isEmpty);
    String workDir = path.absolute(
        path.normalize('${locationProperties.workDir}/${submission.id}/$workingDirectory')
    );
    if (!runTargetIsScript && executable.startsWith('/')) {
      executable = path.absolute(
          path.normalize('${locationProperties.workDir}/${submission.id}/$executable')
      );
    }
    environment ??= io.Platform.environment;
    final ioProcess = await io.Process.start(
      executable,
      arguments,
      workingDirectory: workDir,
      environment: environment,
    );

    Future<int> realPid = Future.value(ioProcess.pid);

    return YajudgeProcess(
      realPid: realPid,
      cgroupDirectory: '',
      ioProcess: ioProcess
    );
  }

  @override
  void killProcess(YajudgeProcess process) {
    process.ioProcess.kill(io.ProcessSignal.sigkill);
  }

  @override
  String submissionPrivateDirectory(Submission submission) {
    return '${locationProperties.workDir}/${submission.id}';
  }

  @override
  String submissionWorkingDirectory(Submission submission) {
    return '${locationProperties.workDir}/${submission.id}';
  }

  @override
  String submissionProblemDirectory(Submission submission) {
    return '${locationProperties.workDir}/${submission.id}';
  }

  @override
  String submissionRootPrefix(Submission submission) {
    return submissionWorkingDirectory(submission);
  }

  @override
  String submissionFileSystemRootPrefix(Submission submission) {
    return '/';
  }

}