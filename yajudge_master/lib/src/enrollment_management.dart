import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:yajudge_common/yajudge_common.dart';

import 'master_service.dart';

class EnrollmentManagementService extends EnrollmentsManagerServiceBase {
  final PostgreSQLConnection connection;
  final MasterService parent;
  final Logger log = Logger('EnrollmentsManager');

  EnrollmentManagementService({required this.parent, required this.connection}): super();

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
      course.id = Int64(row.first);
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
      course.id = Int64(row.first);
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
  Future<GroupEnrollmentsResponse> getGroupEnrollments(ServiceCall call, GroupEnrollmentsRequest request) async {
    int courseId = request.course.id.toInt();
    if (courseId == 0) {
      if (request.course.urlPrefix.isEmpty) {
        throw GrpcError.invalidArgument('both course id and course url prefix not set');
      }
      final urlPrefix = request.course.urlPrefix;
      final coursesService = parent.courseManagementService;
      Course course = await coursesService.getCourseInfoByUrlPrefix(urlPrefix);
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
      return GroupEnrollmentsResponse();
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
      final usersService = parent.userManagementService;
      for (final entry in source) {
        final withProfile = await usersService.getUserById(entry.id);
        result.add(withProfile);
      }
      return result;
    }

    return GroupEnrollmentsResponse(
      id: Int64(groupEnrollmentId),
      groupPattern: pattern,
      groupStudents: await updateUserProfiles(groupStudents),
      foreignStudents: await updateUserProfiles(foreignStudents),
      teachers: await updateUserProfiles(teachers),
      assistants: await updateUserProfiles(assistants),
    );
  }

  @override
  Future<UserEnrollmentsResponse> getUserEnrollments(ServiceCall call, User request) async {
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
        course: Course(id: Int64(coursesId)),
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
        course: Course(id: Int64(coursesId)),
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
      final service = parent.courseManagementService;
      List<Enrollment> result = [];
      for (final entry in source) {
        final courseWithInfo = await service.getCourseInfo(entry.course.id);
        result.add(Enrollment(
          user: entry.user,
          role: entry.role,
          course: courseWithInfo,
        ));
      }
      return result;
    }

    return UserEnrollmentsResponse(
      enrollments: await updateCourseInfo(result),
    );
  }

  @override
  Future<AllGroupsEnrollmentsResponse> getAllGroupsEnrollments(ServiceCall call, Course request) async {
    final urlPrefix = request.urlPrefix;
    final coursesService = parent.courseManagementService;
    request = await coursesService.getCourseInfoByUrlPrefix(urlPrefix);

    final patternsQuery = 'select group_pattern from group_enrollments where courses_id=@id';
    final patternsRows = await connection.query(patternsQuery, substitutionValues: {'id': request.id.toInt()});

    List<GroupEnrollmentsResponse> groups = [];
    for (final row in patternsRows) {
      String pattern = row.single;
      final groupRequest = GroupEnrollmentsRequest(course: request, groupPattern: pattern);
      final groupResponse = await getGroupEnrollments(call, groupRequest);
      groups.add(groupResponse);
    }

    return AllGroupsEnrollmentsResponse(course: request, groups: groups);
  }


}