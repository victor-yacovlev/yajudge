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
  Future<Course> enrollUser(ServiceCall call, Enroll request) async {
    User user = request.user;
    Course course = request.course;
    Role role = request.role;
    if (user.id == 0 && user.email.isEmpty) {
      throw GrpcError.invalidArgument('user id or email required');
    } else if (user.id == 0) {
      List<dynamic> rows = await connection.query(
          'select id from users where email=@email',
          substitutionValues: {'email': user.email});
      List<dynamic> row = rows.first;
      user.id = Int64(row.first);
    }
    if (role == Role.ROLE_ANY) {
      throw GrpcError.invalidArgument('exact role required');
    }
    if (course.id == 0 && course.name.isEmpty) {
      throw GrpcError.invalidArgument('course id or name required');
    } else if (course.id == 0) {
      List<dynamic> rows = await connection.query(
          'select id from courses where name=@name',
          substitutionValues: {'name': course.name});
      List<dynamic> row = rows.first;
      course.id = Int64(row.first);
    } else if (course.name.isEmpty) {
      List<dynamic> rows = await connection.query(
          'select name from courses where id=@id',
          substitutionValues: {'id': course.id.toInt()});
      List<dynamic> row = rows.first;
      course.name = row.first;
    }
    await connection.query(
        'insert into enrollments(courses_id, users_id, role) values (@c,@u,@r)',
        substitutionValues: {
          'c': course.id.toInt(),
          'u': user.id.toInt(),
          'r': role.value,
        });
    return course;
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

  @override
  Future<CourseContentResponse> getCoursePublicContent(ServiceCall? call, CourseContentRequest request) async {
    String courseId = request.courseDataId;
    if (courseId.isEmpty) {
      throw GrpcError.invalidArgument('course data id is required');
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

  @override
  Future<CoursesList> getCourses(ServiceCall call, CoursesFilter filter) async {
    List<Enrollment> enrollments = List.empty(growable: true);
    if (filter.user.id > 0) {
      enrollments = await getUserEnrollments(filter.user);
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
        if (!enrollmentFound) {
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

  Future<List<Enrollment>> getUserEnrollments(User user) async {
    assert(user.id > 0);
    List<Enrollment> enrollments = List.empty(growable: true);
    List<dynamic> rows = await connection.query(
        'select courses_id, role from enrollments where users_id=@id',
        substitutionValues: {'id': user.id.toInt()});
    for (List<dynamic> fields in rows) {
      Course course = Course();
      int courseId = fields[0];
      int role = fields[1];
      course.id = Int64(courseId);
      Enrollment enrollment = Enrollment();
      enrollment.course = course;
      enrollment.role = Role.valueOf(role)!;
      enrollments.add(enrollment);
    }
    return enrollments;
  }

}
