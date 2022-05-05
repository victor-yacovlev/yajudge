import 'dart:io' as io;

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:postgres/postgres.dart';
import 'package:tuple/tuple.dart';
import 'package:xml/xml.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:yaml/yaml.dart';
import 'package:posix/posix.dart' as posix;

import './master_service.dart';
import './user_management.dart';

const CourseReloadInterval = Duration(seconds: 15);

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

DateTime getFileLastModifiedUsingPosixCall(io.File file) {
  // Workaround on bug in Dart runtime that caches file last modified
  // time on first call and not usable to check file changes.
  // This function is passed to CourseLoader and cannot be
  // linked into yajudge_common package due to posix package is
  // incompatible with Dart web target.
  String filePath = normalize(absolute(file.path));
  posix.Stat stat = posix.stat(filePath);
  DateTime result = stat.lastModified;
  return result;
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
  Future<Nothing> deleteCourse(ServiceCall call, Course course) async {
    if (course.id == 0) {
      throw GrpcError.invalidArgument('course id required');
    }
    connection.query('delete from courses where id=@id',
        substitutionValues: {'id': course.id.toInt()});
    return Nothing();
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
      loader.customFileDateTimePicker = getFileLastModifiedUsingPosixCall;
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
      log.severe('cant load problem $courseId/$problemId into cache: $error');
      throw GrpcError.internal('cant load problem $courseId/$problemId into cache');
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
      loader.customFileDateTimePicker = getFileLastModifiedUsingPosixCall;
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
      DateTime lastModified = loader.courseLastModified();
      if (lastModified.millisecondsSinceEpoch > request.cachedTimestamp.toInt()) {
        CourseData courseData = loader.courseData();
        log.fine('sent course data on $courseId to client');
        return CourseContentResponse(
          status: ContentStatus.HAS_DATA,
          courseDataId: courseId,
          data: courseData,
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
      log.severe('cant load course $courseId into cache: $error');
      throw GrpcError.internal('cant load course $courseId into cache');
    }
  }

  Future<Course> getCourseInfo(Int64 id) async {
    final query = '''
    select 
      name, course_data, url_prefix, no_teacher_mode
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
    bool no_teacher_mode = row[3];
    return Course(
      id: id,
      name: name,
      dataId: dataId,
      urlPrefix: urlPrefix,
      noTeacherMode: no_teacher_mode,
    );
  }

  Future<Course> getCourseInfoByUrlPrefix(String urlPrefix) async {
    final query = '''
    select 
      id, name, course_data, no_teacher_mode
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
    bool no_teacher_mode = row[3];
    return Course(
      id: Int64(id),
      name: name,
      dataId: dataId,
      urlPrefix: urlPrefix,
      noTeacherMode: no_teacher_mode,
    );
  }

  @override
  Future<CoursesList> getCourses(ServiceCall call, CoursesFilter filter) async {
    List<Enrollment> enrollments = [];
    final enrollmentsService = parent.enrollmentManagementService;
    final usersService = parent.userManagementService;
    bool userIsAdministrator = false;
    if (filter.user.id > 0) {
      enrollments = (await enrollmentsService.getUserEnrollments(call, filter.user)).enrollments;
      // check if user is really administrator
      if (filter.user.defaultRole == Role.ROLE_ADMINISTRATOR) {
        User userProfile = await usersService.getUserById(filter.user.id);
        userIsAdministrator =
            userProfile.defaultRole == Role.ROLE_ADMINISTRATOR;
      }
    }
    List<dynamic> allCourses = await connection
        .query('select id,name,course_data,url_prefix,no_teacher_mode from courses');
    List<CoursesList_CourseListEntry> res = List.empty(growable: true);
    for (List<dynamic> row in allCourses) {
      Course candidate = Course();
      candidate.id = Int64(row[0]);
      candidate.name = row[1];
      candidate.dataId = row[2];
      candidate.urlPrefix = row[3];
      candidate.noTeacherMode = row[4];
      Role courseRole = Role.ROLE_STUDENT;
      if (enrollments.isNotEmpty) {
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
      } else if (filter.user.id > 0) {
        courseRole =
            await parent.userManagementService.getDefaultRole(filter.user);
      }
      if (filter.course.id > 0 && filter.course.id != candidate.id) {
        continue;
      }
      if (filter.course.name.isNotEmpty) {
        if (!UserManagementService.partialStringMatch(
            filter.partialStringMatch, candidate.name, filter.course.name)) {
          continue;
        }
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
    int courseId = request.course.id.toInt();
    final enrolledUsersRows = await connection.query(
      '''
      select users_id from enrollments
      where courses_id=@course_id and role=@role_student
      ''',
      substitutionValues: {
        'course_id': courseId,
        'role_student': Role.ROLE_STUDENT.value
      },
    );
    List<CourseStatus> statuses = [];
    for (final userRow in enrolledUsersRows as List<dynamic>) {
      int userId = (userRow as List<dynamic>).single;
      final user = await parent.userManagementService.getUserById(Int64(userId));
      if (request.nameFilter.isNotEmpty) {
        final filter = request.nameFilter.trim().toUpperCase();
        bool test1 = user.lastName.toUpperCase().contains(filter);
        bool test2 = user.firstName.toUpperCase().contains(filter);
        bool test3 = (user.firstName + ' ' + user.lastName).toUpperCase().contains(filter);
        bool test4 = (user.lastName + ' ' + user.firstName).toUpperCase().contains(filter);
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
    final statusComparator = (CourseStatus a, CourseStatus b) {
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
    };
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
