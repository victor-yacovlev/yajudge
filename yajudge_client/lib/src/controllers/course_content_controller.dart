import 'package:fixnum/fixnum.dart';
import 'package:tuple/tuple.dart';
import 'package:yajudge_common/yajudge_common.dart';

import 'connection_controller.dart';

class CourseContentController {

  static CourseContentController? instance;
  final Map<String,CourseDataCacheItem> _courseDataCache = {};
  List<CoursesList_CourseListEntry> _coursesList = [];

  static void initialize() {
    instance = CourseContentController();
  }

  Future<Tuple2<Course,Role>> loadCourseByPrefix(User currentUser, String courseUrlPrefix) async {
    final filter = CoursesFilter(user: currentUser);
    if (_coursesList.isEmpty) {
      _coursesList =
      (await ConnectionController.instance!.coursesService.getCourses(filter)).courses;
    }
    for (final entry in _coursesList) {
      if (entry.course.urlPrefix == courseUrlPrefix) {
        return Tuple2(entry.course, entry.role);
      }
    }
    return Tuple2(Course(), Role.ROLE_ANY);
  }

  Future<CourseData> loadCourseData(String courseDataId) async {
    if (!_requiresReload(courseDataId)) {
      return _courseDataCache[courseDataId]!.data!;
    }
    DateTime lastModified = DateTime.fromMillisecondsSinceEpoch(0);
    if (_courseDataCache.containsKey(courseDataId)) {
      final item = _courseDataCache[courseDataId];
      if (item!.lastModified != null) {
        lastModified = item.lastModified!;
      }
    }
    final request = CourseContentRequest(
      courseDataId: courseDataId,
      cachedTimestamp: Int64(lastModified.millisecondsSinceEpoch),
    );
    final response = await ConnectionController.instance!.contentService.getCoursePublicContent(request);
    if (response.status == ContentStatus.HAS_DATA) {
      final newItem = CourseDataCacheItem(
        data: response.data,
        lastModified: DateTime.fromMillisecondsSinceEpoch(response.lastModified.toInt()),
        lastChecked: DateTime.now(),
      );
      _courseDataCache[courseDataId] = newItem;
    }
    return _courseDataCache[courseDataId]!.data!;
  }

  bool _requiresReload(String courseDataId) {
    if (!_courseDataCache.containsKey(courseDataId)) {
      return true;
    }
    CourseDataCacheItem item = _courseDataCache[courseDataId]!;
    if (item.lastModified==null || item.lastChecked==null || item.data==null) {
      return true;
    }
    DateTime lastChecked = item.lastChecked!;
    DateTime nextCheck = lastChecked.add(courseReloadInterval);
    DateTime now = DateTime.now();
    return now.millisecondsSinceEpoch >= nextCheck.millisecondsSinceEpoch;
  }

}