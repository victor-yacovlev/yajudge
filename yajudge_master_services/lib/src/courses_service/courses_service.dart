import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:yajudge_common/yajudge_common.dart';

import '../service_call_extension.dart';
import '../services_connector.dart';


class CourseManagementService extends CourseManagementServiceBase {
  final PostgreSQLConnection connection;
  final Logger log = Logger('CoursesManager');
  final String secretKey;
  final ServicesConnector services;

  CourseManagementService({
    required this.connection,
    required this.secretKey,
    required this.services,
  }) : super();


  @override
  Future<CoursesList> getCourses(ServiceCall call, CoursesFilter request) async {
    User? currentUser = call.getSessionUser(secretKey);
    if (currentUser == null) {
      log.warning('current user from session is null while getting courses list, client metadata is ${call.clientMetadata}');
      throw GrpcError.unauthenticated('requires user authentication to get courses list');
    }
    if (services.users == null) {
      final message = 'users service offline while GetCourses';
      log.severe(message);
      throw GrpcError.unavailable(message);
    }
    currentUser = await services.users!.getProfileById(currentUser,
      options: CallOptions(metadata: call.clientMetadata),
    );
    final userEnrollments = await getUserEnrollments(call, currentUser);
    final userIsAdministrator = currentUser.defaultRole == Role.ROLE_ADMINISTRATOR;
    List<dynamic> allCourses = await connection
        .query('select id,name,course_data,url_prefix,disable_review,disable_defence,description from courses');
    List<CoursesList_CourseListEntry> res = List.empty(growable: true);
    for (List<dynamic> row in allCourses) {
      Course candidate = Course();
      candidate.id = row[0];
      candidate.name = row[1];
      candidate.dataId = row[2];
      candidate.urlPrefix = row[3];
      candidate.disableReview = row[4];
      candidate.disableDefence = row[5];
      candidate.description = row[6] ?? '';
      Role courseRole = Role.ROLE_STUDENT;
      bool enrollmentFound = false;
      for (final enr in userEnrollments.enrollments) {
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
  Future<EnrollGroupRequest> enrollGroup(ServiceCall call, EnrollGroupRequest request) async {
    Course course = request.course;
    if (course.id == 0 && course.name.isEmpty) {
      throw GrpcError.invalidArgument('course id or name required');
    } else if (course.id == 0) {
      List<dynamic> rows = await connection.query(
          'select id from courses where name=@name',
          substitutionValues: {'name': course.name});
      List<dynamic> row = rows.first;
      course.id = row.single;
    } else if (course.name.isEmpty) {
      List<dynamic> rows = await connection.query(
          'select name from courses where id=@id',
          substitutionValues: {'id': course.id.toInt()});
      List<dynamic> row = rows.first;
      course.name = row.first;
    }
    await connection.query(
        'insert into group_enrollments(courses_id,group_pattern) values (@c,@p)',
        substitutionValues: {
          'c': course.id.toInt(),
          'p': request.groupPattern.trim(),
        }
    );
    return request;
  }

  @override
  Future<EnrollUserRequest> enrollUser(ServiceCall call, EnrollUserRequest request) async {
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
      course.id = row.single;
    } else if (course.name.isEmpty) {
      List<dynamic> rows = await connection.query(
          'select name from courses where id=@id',
          substitutionValues: {'id': course.id.toInt()});
      List<dynamic> row = rows.first;
      course.name = row.first;
    }
    await connection.query(
        'insert into personal_enrollments(courses_id,users_id,role,group_pattern) values (@c,@u,@r,@p)',
        substitutionValues: {
          'c': course.id.toInt(),
          'u': user.id.toInt(),
          'r': role.value,
          'p': request.groupPattern.trim(),
        });
    return request;
  }

  @override
  Future<GroupEnrollments> getGroupEnrollments(ServiceCall call, GroupEnrollmentsRequest request) async {
    int courseId = request.course.id.toInt();
    if (courseId == 0) {
      if (request.course.urlPrefix.isEmpty) {
        throw GrpcError.invalidArgument('both course id and course url prefix not set');
      }
      Course course = await getCourse(call, request.course);
      courseId = course.id.toInt();
    }
    final pattern = request.groupPattern;
    final groupQuery = '''
    select 
      id
    from
      group_enrollments
    where
      group_pattern=@p and courses_id=@id 
    ''';
    final groupRows = await connection.query(groupQuery,
        substitutionValues: {
          'p': pattern,
          'id': courseId,
        }
    );
    if (groupRows.isEmpty) {
      return GroupEnrollments();
    }

    int groupEnrollmentId = groupRows.first[0];

    final groupStudentsQuery = '''
    select
      id
    from
      users
    where
      default_role=@role_student
      and
      strpos(group_name, @pattern)>0
    ''';
    final groupStudentsRows = await connection.query(groupStudentsQuery,
        substitutionValues: {
          'role_student': Role.ROLE_STUDENT.value,
          'pattern': pattern,
        }
    );

    final excludedStudentsQuery = '''
    select
      users_id
    from
      users, personal_enrollments
    where
      courses_id=@courses_id
      and
      users.id=users_id
      and
      group_pattern<>@pattern
      and
      strpos(group_name, @pattern)>0
      and
      role=@role_student
    ''';
    final excludedStudentsRows = await connection.query(excludedStudentsQuery,
        substitutionValues: {
          'courses_id': courseId,
          'pattern': pattern,
          'role_student': Role.ROLE_STUDENT.value,
        }
    );
    List<User> groupStudents = [];
    for (final groupStudentRow in groupStudentsRows) {
      int userId = groupStudentRow[0];
      bool excluded = false;
      for (final excludedRow in excludedStudentsRows) {
        int excludedId = excludedRow[0];
        if (excludedId == userId) {
          excluded = true;
          break;
        }
      }
      if (excluded) {
        continue;
      }
      groupStudents.add(User(id: Int64(userId)));
    }

    final personalQuery = '''
    select 
      users_id
    from 
      personal_enrollments, users
    where
      strpos(group_name, group_pattern)>0
      and
      users_id=users.id
      and
      role=@role
      and
      courses_id=@courses_id
    ''';

    final foreignStudentsRows = await connection.query(personalQuery,
        substitutionValues: {
          'role': Role.ROLE_STUDENT.value,
          'courses_id': courseId,
        }
    );

    final teacherQuery = '''
    select
      users_id
    from
      personal_enrollments
    where
      role=@role
      and
      courses_id=@courses_id
      and
      group_pattern=@pattern
    ''';
    final teachersRows = await connection.query(teacherQuery,
        substitutionValues: {
          'role': Role.ROLE_TEACHER.value,
          'courses_id': courseId,
          'pattern': pattern,
        }
    );
    final assistantsRows = await connection.query(teacherQuery,
        substitutionValues: {
          'role': Role.ROLE_TEACHER_ASSISTANT.value,
          'courses_id': courseId,
          'pattern': pattern,
        }
    );

    User rowToUser(final row) {
      int id = row[0];
      return User(id: Int64(id));
    }

    List<User> foreignStudents = List.of(List.of(foreignStudentsRows).map(rowToUser));
    List<User> teachers = List.of(List.of(teachersRows).map(rowToUser));
    List<User> assistants = List.of(List.of(assistantsRows).map(rowToUser));

    Future<List<User>> updateUserProfiles(List<User> source) async {
      List<User> result = [];
      for (final entry in source) {
        if (services.users == null) {
          final message = 'users service offline while GetGroupEnrollments';
          log.severe(message);
          throw GrpcError.unavailable(message);
        }
        final withProfile = await services.users!.getProfileById(entry,
          options: CallOptions(metadata: call.clientMetadata),
        );
        result.add(withProfile);
      }
      return result;
    }

    return GroupEnrollments(
      id: groupEnrollmentId,
      groupPattern: pattern,
      groupStudents: await updateUserProfiles(groupStudents),
      foreignStudents: await updateUserProfiles(foreignStudents),
      teachers: await updateUserProfiles(teachers),
      assistants: await updateUserProfiles(assistants),
    );
  }

  @override
  Future<UserEnrollments> getUserEnrollments(ServiceCall call, User request) async {
    List<Enrollment> result = [];

    // Group-wide enrollments

    final groupQuery = '''
    select 
      courses_id, group_pattern 
    from 
      group_enrollments, users 
    where 
        strpos(group_name, group_pattern)>0
      and
        users.id=@id
    ''';
    final groupRows = await connection.query(groupQuery,
        substitutionValues: { 'id': request.id.toInt() }
    );
    for (final row in groupRows) {
      int coursesId = row[0];
      String pattern = row[1];
      result.add(Enrollment(
        course: Course(id: coursesId),
        role: Role.ROLE_STUDENT,
        groupPattern: pattern,
        user: request,
      ));
    }

    // Personal enrollments - might override group enrollments

    final personalQuery = '''
    select
      courses_id, role, group_pattern
    from 
      personal_enrollments
    where
      users_id=@id
    ''';
    final personalRows = await connection.query(personalQuery,
        substitutionValues: { 'id': request.id.toInt() }
    );
    final groupEnrollmentsCount = result.length;
    for (final row in personalRows) {
      int coursesId = row[0];
      int roleValue = row[1];
      Role role = Role.valueOf(roleValue)!;
      String pattern = row[2];
      final personalEnrollment = Enrollment(
        user: request,
        course: Course(id: coursesId),
        role: role,
        groupPattern: pattern,
      );
      bool overridesGroupEnrollment = false;
      for (int i=0; i<groupEnrollmentsCount; ++i) {
        final groupEnrollment = result[i];
        if (groupEnrollment.course.id == personalEnrollment.course.id) {
          if (personalEnrollment.role == Role.ROLE_STUDENT) {
            // students might be enrolled to not their groups
            if (personalEnrollment.groupPattern.isNotEmpty &&
                personalEnrollment.groupPattern!=groupEnrollment.groupPattern) {
              result[i] = personalEnrollment;
              overridesGroupEnrollment = true;
            }
          }
        }
      }
      if (!overridesGroupEnrollment) {
        result.add(personalEnrollment);
      }
    }

    Future<List<Enrollment>> updateCourseInfo(List<Enrollment> source) async {
      List<Enrollment> result = [];
      for (final entry in source) {
        final courseWithInfo = await getCourse(null, entry.course);
        result.add(Enrollment(
          user: entry.user,
          role: entry.role,
          course: courseWithInfo,
        ));
      }
      return result;
    }

    return UserEnrollments(
      enrollments: await updateCourseInfo(result),
    );
  }

  @override
  Future<AllGroupsEnrollments> getAllGroupsEnrollments(ServiceCall call, Course request) async {
    final patternsQuery = 'select group_pattern from group_enrollments where courses_id=@id';
    final patternsRows = await connection.query(patternsQuery, substitutionValues: {'id': request.id.toInt()});

    List<GroupEnrollments> groups = [];
    for (final row in patternsRows) {
      String pattern = row.single;
      final groupRequest = GroupEnrollmentsRequest(course: request, groupPattern: pattern);
      final groupResponse = await getGroupEnrollments(call, groupRequest);
      groups.add(groupResponse);
    }

    return AllGroupsEnrollments(course: request, groups: groups);
  }

  @override
  Future<Course> getCourse(ServiceCall? call, Course request) async {
    if (request.id <= 0 && request.urlPrefix.trim().isEmpty) {
      throw GrpcError.invalidArgument('requires course id or url prefix');
    }
    String query = '''
    select 
      id,name,course_data,url_prefix,description,
      disable_review,disable_defence     
    from courses
    where ''';
    final params = <String,dynamic>{};
    if (request.id > 0) {
      query += ' id=@id';
      params['id'] = request.id;
    }
    else {
      query += ' url_prefix=@prefix';
      params['prefix'] = request.urlPrefix.trim();
    }
    PostgreSQLResult rows;
    try {
      rows = await connection.query(query, substitutionValues: params);
    }
    catch (e) {
      log.severe('while accessing sql statement `$query` with params=$params on GetCourses: $e');
      rethrow;
    }
    if (rows.isEmpty) {
      throw GrpcError.notFound('no such course: $params');
    }
    final row = rows.first;
    return Course(
      id: row[0], name: row[1], dataId: row[2], urlPrefix: row[3],
      description: row[4], disableReview: row[5], disableDefence: row[6],
    );
  }

}
