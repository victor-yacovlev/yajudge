import 'package:fixnum/fixnum.dart';
import 'package:yajudge_common/yajudge_common.dart';

import 'connection_controller.dart';

class CoursesController {

  static CoursesController? instance;
  Map<String,CourseDataCacheItem> _courseDataCache = {};

  static void initialize() {
    assert(instance == null);
    instance = CoursesController();
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
    final response = await ConnectionController.instance!.coursesService.getCoursePublicContent(request);
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
    DateTime nextCheck = lastChecked.add(CourseReloadInterval);
    DateTime now = DateTime.now();
    return now.millisecondsSinceEpoch >= nextCheck.millisecondsSinceEpoch;
  }

}