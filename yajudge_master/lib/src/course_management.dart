import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:protobuf/protobuf.dart';
import 'package:yajudge_common/yajudge_common.dart';

import './master_service.dart';

const courseReloadInterval = Duration(seconds: 15);

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

class CourseManagementService extends CourseManagementServiceBase {
  final PostgreSQLConnection connection;
  final MasterService parent;
  final MasterLocationProperties locationProperties;
  final Map<String,CourseLoader> courseLoaders = {};
  final Logger log = Logger('CoursesManager');

  CourseManagementService(
      {required this.parent, required this.connection, required this.locationProperties})
      : super();

  @override
  Future<Course> cloneCourse(ServiceCall call, Course request) {
    // TODO: implement cloneCourse
    throw UnimplementedError();
  }

  @override
  Future<Course> createOrUpdateCourse(ServiceCall call, Course request) {
    // TODO: implement createOrUpdateCourse
    throw UnimplementedError();
  }

  @override
  Future<Nothing> deleteCourse(ServiceCall call, Course request) async {
    if (request.id == 0) {
      throw GrpcError.invalidArgument('course id required');
    }
    connection.query('delete from courses where id=@id',
        substitutionValues: {'id': request.id.toInt()});
    return Nothing();
  }

  ProblemMetadata getProblemMetadata(Course course, String problemId) {
    final courseId = course.dataId;
    if (courseId.isEmpty || problemId.isEmpty) {
      throw GrpcError.invalidArgument('course data id and problem id are required');
    }
    final courseData = getCourseData(courseId);
    return courseData.findProblemMetadataById(problemId);
  }

  @override
  Future<ProblemContentResponse> getProblemFullContent(ServiceCall? call, ProblemContentRequest request) async {
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
        ProblemData problemData = loader.problemData(problemId);
        log.fine('sent problem data on $courseId/$problemId [last modified $lastModified] to grader');
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

  CourseData getCourseData(String courseId) {
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

  @override
  Future<CourseContentResponse> getCoursePublicContent(ServiceCall? call, CourseContentRequest request) async {
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

  Future<Course> getCourseInfo(Int64 id) async {
    final query = '''
    select 
      name, course_data, url_prefix, disable_review, disable_defence, course_start
    from courses
    where id=@id
    ''';
    final rows = await connection.query(query, substitutionValues: {'id': id.toInt()});
    if (rows.isEmpty) {
      throw GrpcError.notFound('course with id=$id not found while getting course info');
    }
    final row = rows.single;
    String name = row[0];
    String dataId = row[1];
    String urlPrefix = row[2];
    bool skipReview = row[3];
    bool skipDefence = row[4];
    DateTime courseStart = row[5] is DateTime? row[5] as DateTime : DateTime.fromMicrosecondsSinceEpoch(0);
    return Course(
      id: id,
      name: name,
      dataId: dataId,
      urlPrefix: urlPrefix,
      disableReview: skipReview,
      disableDefence: skipDefence,
      courseStart: Int64(courseStart.millisecondsSinceEpoch ~/ 1000),
    );
  }

  Future<Course> getCourseInfoByUrlPrefix(String urlPrefix) async {
    final query = '''
    select 
      id, name, course_data, disable_review, disable_defence, course_start
    from courses
    where url_prefix=@url_prefix
    ''';
    final rows = await connection.query(query, substitutionValues: {'url_prefix': urlPrefix});
    if (rows.isEmpty) {
      throw GrpcError.notFound('course with url_prefix=$urlPrefix not found while getting course info');
    }
    final row = rows.single;
    int id = row[0];
    String name = row[1];
    String dataId = row[2];
    bool skipReview = row[3];
    bool skipDefence = row[4];
    DateTime courseStart = row[5] is DateTime? row[5] as DateTime : DateTime.fromMicrosecondsSinceEpoch(0);
    return Course(
      id: Int64(id),
      name: name,
      dataId: dataId,
      urlPrefix: urlPrefix,
      disableReview: skipReview,
      disableDefence: skipDefence,
      courseStart: Int64(courseStart.millisecondsSinceEpoch ~/ 1000),
    );
  }

  @override
  Future<CoursesList> getCourses(ServiceCall call, CoursesFilter request) async {
    List<Enrollment> enrollments = [];
    final enrollmentsService = parent.enrollmentManagementService;
    final usersService = parent.userManagementService;
    bool userIsAdministrator = false;
    if (request.user.id > 0) {
      enrollments = (await enrollmentsService.getUserEnrollments(call, request.user)).enrollments;
      // check if user is really administrator
      if (request.user.defaultRole == Role.ROLE_ADMINISTRATOR) {
        User userProfile = await usersService.getUserById(request.user.id);
        userIsAdministrator =
            userProfile.defaultRole == Role.ROLE_ADMINISTRATOR;
      }
    }
    List<dynamic> allCourses = await connection
        .query('select id,name,course_data,url_prefix,disable_review,disable_defence,course_start from courses');
    List<CoursesList_CourseListEntry> res = List.empty(growable: true);
    for (List<dynamic> row in allCourses) {
      Course candidate = Course();
      candidate.id = Int64(row[0]);
      candidate.name = row[1];
      candidate.dataId = row[2];
      candidate.urlPrefix = row[3];
      candidate.disableReview = row[4];
      candidate.disableDefence = row[5];
      DateTime courseStart = row[6] is DateTime? row[6] as DateTime : DateTime.fromMicrosecondsSinceEpoch(0);
      candidate.courseStart = Int64(courseStart.millisecondsSinceEpoch ~/ 1000);
      Role courseRole = Role.ROLE_STUDENT;
      bool enrollmentFound = false;
      for (Enrollment enr in enrollments) {
        if (enr.course.id == candidate.id) {
          enrollmentFound = true;
          courseRole = enr.role;
          break;
        }
      }
      if (!enrollmentFound && !userIsAdministrator) {
        continue;
      }
      CoursesList_CourseListEntry entry = CoursesList_CourseListEntry();
      entry.course = candidate;
      entry.role = courseRole;
      res.add(entry);
    }
    CoursesList result = CoursesList(courses: res);
    return result;
  }

  @override
  Future<CourseProgressResponse> getProgress(ServiceCall call, CourseProgressRequest request) async {
    final enrollmentService = parent.enrollmentManagementService;
    final enrollment = await enrollmentService.getAllGroupsEnrollments(call, request.course);
    List<User> enrolledUsers = [];
    for (final group in enrollment.groups) {
      enrolledUsers.addAll(group.groupStudents);
      enrolledUsers.addAll(group.foreignStudents);
    }
    List<CourseStatus> statuses = [];
    for (final user in enrolledUsers) {
      if (request.nameFilter.isNotEmpty) {
        final filter = request.nameFilter.trim().toUpperCase();
        bool test1 = user.lastName.toUpperCase().contains(filter);
        bool test2 = user.firstName.toUpperCase().contains(filter);
        bool test3 = ('${user.firstName} ${user.lastName}').toUpperCase().contains(filter);
        bool test4 = ('${user.lastName} ${user.firstName}').toUpperCase().contains(filter);
        bool test5 = user.groupName.toUpperCase().contains(filter);
        bool matched = test1 || test2 || test3 || test4 || test5;
        if (!matched) {
          continue;
        }
      }
      final statusRequest = CheckCourseStatusRequest(user: user, course: request.course);
      final statusResponse = await parent.submissionManagementService.checkCourseStatus(call, statusRequest);
      statuses.add(statusResponse);
    }
    int statusComparator(CourseStatus a, CourseStatus b) {
      if (a.user.groupName == b.user.groupName) {
        if (a.user.lastName == b.user.lastName) {
          if (a.user.firstName == b.user.firstName) {
            return a.user.midName.compareTo(b.user.midName);
          }
          else {
            return a.user.firstName.compareTo(b.user.firstName);
          }
        }
        else {
          return a.user.lastName.compareTo(b.user.lastName);
        }
      }
      else {
        return a.user.groupName.compareTo(b.user.groupName);
      }
    }
    statuses.sort(statusComparator);
    List<ProblemData> problems = [];
    if (request.includeProblemDetails) {
      final courseData = await getCoursePublicContent(call, CourseContentRequest(courseDataId: request.course.dataId));
      for (final section in courseData.data.sections) {
        for (final lesson in section.lessons) {
          problems.addAll(lesson.problems);
        }
      }
    }
    List<CourseStatusEntry> entries = [];
    for (final status in statuses) {
      double scoreGot = status.scoreGot;
      double scoreMax = status.scoreMax;
      bool courseCompleted = status.completed;
      List<ProblemStatus> problemStatuses = [];
      if (request.includeProblemDetails) {
        for (final section in status.sections) {
          for (final lesson in section.lessons) {
            problemStatuses.addAll(lesson.problems);
          }
        }
      }
      final entry = CourseStatusEntry(
        user: status.user,
        scoreGot: scoreGot,
        scoreMax: scoreMax,
        courseCompleted: courseCompleted,
        statuses: problemStatuses,
      );
      entries.add(entry);
    }
    return CourseProgressResponse(entries: entries, problems: problems);
  }

}
