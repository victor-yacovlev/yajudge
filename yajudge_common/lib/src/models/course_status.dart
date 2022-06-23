import '../../yajudge_common.dart';

extension CourseStatusExtension on CourseStatus {
  ProblemStatus findProblemStatus(String problemId) {
    for (final section in sections) {
      for (final lesson in section.lessons) {
        for (final problem in lesson.problems) {
          if (problem.problemId == problemId) {
            return problem;
          }
        }
      }
    }
    return ProblemStatus();
  }
}