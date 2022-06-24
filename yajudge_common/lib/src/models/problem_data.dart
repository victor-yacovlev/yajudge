import '../../yajudge_common.dart';

extension ProblemDataExtension on ProblemData {

  void cleanPrivateContent() {
    // must be called only after deepCopy

    final limits = gradingOptions.limits;
    final executableTarget = gradingOptions.executableTarget;
    final buildSystem = gradingOptions.buildSystem;
    gradingOptions = GradingOptions(
      limits: limits,
      executableTarget: executableTarget,
      buildSystem: buildSystem,
    );
    graderFiles = FileSet();
  }

}