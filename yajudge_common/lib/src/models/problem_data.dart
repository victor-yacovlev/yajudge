import '../../yajudge_common.dart';

extension ProblemDataExtension on ProblemData {

  void cleanPrivateContent() {
    // must be called only after deepCopy

    final limits = gradingOptions.limits;
    gradingOptions = GradingOptions(limits: limits);
    graderFiles = FileSet();
  }

}