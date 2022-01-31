import 'package:yajudge_common/yajudge_common.dart';
import 'dart:io' as io;

abstract class AbstractRunner {
  void createDirectoryForSubmission(Submission submission);
  void releaseDirectoryForSubmission(Submission submission);
  Future<io.Process> start(int submissionId, String executable, List<String> arguments, {
    String workingDirectory = '/build',
    Map<String,String>? environment,
    GradingLimits? limits,
  });
  String submissionPrivateDirectory(Submission submission);
  String submissionWorkingDirectory(Submission submission);
  String submissionProblemDirectory(Submission submission);
}