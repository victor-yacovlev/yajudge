import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';

import 'services_connector.dart';

class CourseDataConsumer {

  final Map<String,CourseDataCacheItem> loadedCourses = {};
  late final ServicesConnector courseDataConsumerServices;
  final _log = Logger("CourseDataConsumer");

  Future<CourseData> getCourseData(ServiceCall? call, Course course) async {
    int cachedTimestamp = 0;
    CourseDataCacheItem? cacheItem = loadedCourses[course.dataId];
    if (cacheItem != null) {
      cachedTimestamp = cacheItem.lastModified!.millisecondsSinceEpoch ~/ 1000;
    }
    final request = CourseContentRequest(
      courseDataId: course.dataId,
      cachedTimestamp: Int64(cachedTimestamp),
    );
    CallOptions options = CallOptions(metadata: call?.clientMetadata);
    if (courseDataConsumerServices.content == null) {
      final message = 'content service offline';
      _log.severe(message);
      throw GrpcError.unavailable(message);
    }
    final response = await courseDataConsumerServices.content!.getCoursePublicContent(request, options: options);
    CourseData result;
    if (response.status == ContentStatus.HAS_DATA) {
      loadedCourses[course.dataId] = CourseDataCacheItem(
        data: response.data,
        lastChecked: DateTime.now(),
        lastModified: DateTime.fromMillisecondsSinceEpoch(1000 * response.lastModified.toInt()),
      );
      result = response.data;
    }
    else {
      result = cacheItem!.data!;
    }
    return result;
  }

}