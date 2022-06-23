import '../../yajudge_common.dart';

extension CoursesListExtension on CoursesList {
  CoursesList_CourseListEntry? findByUrlPrefix(String urlPrefix) {
    for (final entry in courses) {
      if (entry.course.urlPrefix == urlPrefix) {
        return entry;
      }
    }
    return null;
  }
}
