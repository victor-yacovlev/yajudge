import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:logging/logging.dart';
import 'package:protobuf/protobuf.dart';
import 'dart:math' as math;

class CoursesContentProviderService extends CourseContentProviderServiceBase {

  final MasterLocationProperties locationProperties;
  final courseLoaders = <String,CourseLoader>{};
  final log = Logger('CoursesContentProvider');

  CoursesContentProviderService(this.locationProperties);

  @override
  Future<ProblemContentResponse> getProblemFullContent(ServiceCall call, ProblemContentRequest request) async {
    String courseId = request.courseDataId;
    String problemId = request.problemId;
    if (courseId.isEmpty || problemId.isEmpty) {
      throw GrpcError.invalidArgument('course data id and problem id are required');
    }
    CourseLoader loader;
    if (!courseLoaders.containsKey(courseId)) {
      courseLoaders[courseId] = loader = CourseLoader(
        courseId: courseId,
        coursesRootPath: locationProperties.coursesRoot,
        separateProblemsRootPath: locationProperties.problemsRoot,
      );
    } else {
      loader = courseLoaders[courseId]!;
    }
    try {
      DateTime lastModified = loader.problemLastModified(problemId);
      if (lastModified.millisecondsSinceEpoch > request.cachedTimestamp.toInt()) {
        CourseData courseData = loader.courseData();
        ProblemData problemData = loader.problemData(problemId).deepCopy();
        problemData.gradingOptions.limits = courseData.defaultLimits.mergedWith(problemData.gradingOptions.limits);
        log.fine('sent problem data on $courseId/$problemId [last modified $lastModified]');
        return ProblemContentResponse(
          problemId: problemId,
          courseDataId: courseId,
          status: ContentStatus.HAS_DATA,
          data: problemData,
          lastModified: Int64(lastModified.millisecondsSinceEpoch),
        );
      } else {
        DateTime requestDateTime = DateTime.fromMillisecondsSinceEpoch(request.cachedTimestamp.toInt());
        log.fine('skipped sending problem data on $courseId/$problemId due to no changes [last modified $lastModified, cached $requestDateTime] to grader');
        return ProblemContentResponse(
          problemId: problemId,
          courseDataId: courseId,
          status: ContentStatus.NOT_CHANGED,
          lastModified: Int64(lastModified.millisecondsSinceEpoch),
        );
      }
    } catch (error) {
      String message = 'cant load problem $courseId/$problemId into cache: $error';
      if (error is Error && error.stackTrace!=null) {
        message += '\n${error.stackTrace}';
      }
      log.severe(message);
      throw GrpcError.internal(message);
    }
  }

  @override
  Future<CourseContentResponse> getCoursePublicContent(ServiceCall call, CourseContentRequest request) async {
    String courseId = request.courseDataId;
    if (courseId.isEmpty) {
      throw GrpcError.invalidArgument('course data id is required');
    }
    final loader = _getCourseLoader(courseId);
    try {
      final lastModified = loader.courseLastModified();
      if (lastModified.millisecondsSinceEpoch > request.cachedTimestamp.toInt()) {
        CourseData courseData = loader.courseData();
        CourseData publicCourseData = courseData.deepCopy();
        publicCourseData.cleanPrivateContent();
        log.fine('sent course data on $courseId to client');
        return CourseContentResponse(
          status: ContentStatus.HAS_DATA,
          courseDataId: courseId,
          data: publicCourseData,
          lastModified: Int64(lastModified.millisecondsSinceEpoch),
        );
      } else {
        return CourseContentResponse(
          status: ContentStatus.NOT_CHANGED,
          courseDataId: courseId,
          lastModified: Int64(lastModified.millisecondsSinceEpoch),
        );
      }
    } catch (error) {
      final shortMessage = 'cant load course $courseId into cache: $error';
      log.severe(shortMessage);
      throw GrpcError.internal(shortMessage);
    }
  }

  ProblemMetadata getProblemMetadata(Course course, String problemId) {
    final courseId = course.dataId;
    if (courseId.isEmpty || problemId.isEmpty) {
      throw GrpcError.invalidArgument('course data id and problem id are required');
    }
    final courseData = _getCourseData(courseId);
    return courseData.findProblemMetadataById(problemId);
  }

  CourseData _getCourseData(String courseId) {
    final loader = _getCourseLoader(courseId);
    return loader.courseData();
  }

  CourseLoader _getCourseLoader(String courseId) {
    CourseLoader loader;
    if (!courseLoaders.containsKey(courseId)) {
      courseLoaders[courseId] = loader = CourseLoader(
        courseId: courseId,
        coursesRootPath: locationProperties.coursesRoot,
        separateProblemsRootPath: locationProperties.problemsRoot,
      );
    } else {
      loader = courseLoaders[courseId]!;
    }
    return loader;
  }



}

class CourseDataCacheItem {
  final CourseData? data;
  final DateTime? lastModified;
  final DateTime? lastChecked;
  final GrpcError? loadError;

  CourseDataCacheItem({
    this.data,
    this.lastModified,
    this.lastChecked,
    this.loadError,
  });
}

class ProblemDataCacheItem {
  final ProblemData? data;
  final DateTime? lastModified;
  final DateTime? lastChecked;
  final GrpcError? loadError;

  ProblemDataCacheItem({
    this.data,
    this.lastModified,
    this.lastChecked,
    this.loadError,
  });
}