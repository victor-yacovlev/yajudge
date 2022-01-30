import 'package:logging/logging.dart';
import 'package:yajudge_common/src/generated/yajudge.pb.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:path/path.dart' as path;
import 'dart:io' as io;
import 'abstract_runner.dart';

class SimpleRunner extends AbstractRunner {

  final GraderLocationProperties locationProperties;
  final Logger log = Logger('ChrootedRunner');

  SimpleRunner({required this.locationProperties});

  @override
  void createDirectoryForSubmission(Submission submission) {
    String submissionPath = path.absolute(locationProperties.workDir, '${submission.id}');
    String courseId = submission.course.dataId;
    String problemId = submission.problemId;
    String problemContentPath = path.absolute(locationProperties.coursesCacheDir, courseId, problemId);
    final submissionFilesDir = io.Directory(submissionPath+'/build');
    submissionFilesDir.createSync(recursive: true);
    final problemContent = io.Directory(problemContentPath);
    problemContent.listSync().forEach((element) {
      final copyResult = io.Process.runSync('cp', ['-Rf', element.path, submissionPath]);
      assert(copyResult.exitCode == 0);
    });
    final fileNames = submission.solutionFiles.files.map((e) => e.name);
    io.File(submissionFilesDir.path+'/.solution_files').writeAsStringSync(
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
  void releaseDirectoryForSubmission(Submission submission) {
    // Do nothing to keep data for possible debug
  }

  @override
  Future<io.Process> start(int submissionId, String executable, List<String> arguments, {
    String workingDirectory = '/build',
    Map<String, String>? environment,
    GradingLimits? limits
      })
  {
    String workDir = path.absolute(
        path.normalize('${locationProperties.workDir}/$submissionId/$workingDirectory')
    );
    if (executable.startsWith('/'))
      executable = path.absolute(
          path.normalize('${locationProperties.workDir}/$submissionId/$executable')
      );
    if (environment == null)
      environment = io.Platform.environment;
    return io.Process.start(executable, arguments, workingDirectory: workDir, environment: environment);
  }

  @override
  String submissionPrivateDirectory(Submission submission) {
    return '${locationProperties.workDir}/${submission.id}';
  }

  @override
  String submissionWorkingDirectory(Submission submission) {
    return '${locationProperties.workDir}/${submission.id}';
  }

}