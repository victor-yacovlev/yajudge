import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';

import 'master_service.dart';

class UserManagementService extends UserManagementServiceBase {

  final PostgreSQLConnection connection;
  final Logger log = Logger('UsersManager');
  final MasterService parent;

  UserManagementService({required this.connection, required this.parent}): super();

  @override
  Future<Session> authorize(ServiceCall call, User user) async {
    if (user.id==0 && user.email.isEmpty && user.login.isEmpty) {
      log.warning('empty user id tried to authorize');
      throw GrpcError.invalidArgument('id or email not provided');
    }
    if (user.password.isEmpty) {
      log.warning('user ${user.id} / ${user.email} tried to authorize with no password');
      throw GrpcError.invalidArgument('password not provided');
    }
    if (user.disabled) {
      log.warning('disabled user ${user.id} / ${user.email} tried to authorize');
      throw GrpcError.permissionDenied('user disabled');
    }
    String findByIdQuery = 'select id, password from users where id=@id';
    String findByEmailQuery = 'select id, password from users where email=@email';
    String findByLoginQuery = 'select id, password from users where login=@login';
    List<List<dynamic>> usersRows;
    if (user.id > 0) {
      usersRows = await connection.query(
          findByIdQuery, substitutionValues: {'id': user.id.toInt()}
      );
    } else if (user.email.isNotEmpty) {
      usersRows = await connection.query(
          findByEmailQuery, substitutionValues: {'email': user.email}
      );
    } else {
      usersRows = await connection.query(
          findByLoginQuery, substitutionValues: {'login': user.login}
      );
    }
    if (usersRows.isEmpty) {
      log.warning('not existing user ${user.id} / ${user.email} tried to authorize');
      throw GrpcError.notFound('user not found');
    }
    List<dynamic> singleUserRow = usersRows.single;
    int userId = singleUserRow[0];
    String userPassword = singleUserRow[1];
    bool passwordMatch;
    if (userPassword.startsWith('=')) {
      // plain text password
      passwordMatch = user.password == userPassword.substring(1);
    } else {
      String hexDigest = makePasswordHash(user.password, Int64(userId));
      passwordMatch = userPassword == hexDigest;
    }
    if (!passwordMatch) {
      log.warning('user ${user.id} / ${user.email} tried to authorize with wrong password');
      throw GrpcError.permissionDenied('wrong password');
    }
    final session = await createSessionForAuthenticatedUser(user.copyWith((u) {
      u.id = Int64(userId);
    }));
    log.fine('user ${user.id} / ${user.email} successfully authorized');
    return session;
  }

  Future<Session> createSessionForAuthenticatedUser(User user) async {
    DateTime timestamp = DateTime.now();
    String sessionKey = '${user.id} ${user.email} ${timestamp.millisecondsSinceEpoch}';
    sessionKey = sha256.convert(utf8.encode(sessionKey)).toString();
    Session session = Session(
      cookie: sessionKey,
      start: Int64(timestamp.millisecondsSinceEpoch ~/ 1000),
      user: await getUserById(user.id),
    );
    // try to find existing session first
    List<dynamic> existingSessionsRows = await connection.query(
      'select cookie from sessions where cookie=@c',
      substitutionValues: { 'c': sessionKey },
    );
    if (existingSessionsRows.isEmpty) {
      // create new session if not found
      String storeSessionQuery = 'insert into sessions(cookie, users_id, start) values (@c, @id, @st)';
      await connection.query(storeSessionQuery, substitutionValues: {
        'c': sessionKey, 'id': user.id.toInt(), 'st': timestamp
      });
    }
    return session;
  }

  @override
  Future<UsersList> batchCreateStudents(ServiceCall call, UsersList usersList) async {
    for (User user in usersList.users) {
      user.password = generateRandomPassword();
      user.defaultRole = Role.ROLE_STUDENT;
      user = await createOrUpdateUser(call, user);
    }
    return usersList;
  }

  static String generateRandomPassword() {
    final String alphabet = '01234567abcdef';
    String password = '';
    Random random = Random.secure();
    for (int i=0; i<8; i++) {
      int runeNum = random.nextInt(alphabet.length - 1);
      String rune = alphabet[runeNum];
      password += rune;
    }
    return password;
  }

  @override
  Future<Nothing> batchDeleteUsers(ServiceCall call, UsersList usersList) async {
    if (usersList.users.isEmpty) {
      return Nothing();
    }
    await connection.transaction((connection) async {
      for (User user in usersList.users) {
        await connection.query('delete from personal_enrollments where users_id=@id',
          substitutionValues: {'id': user.id.toInt() }
        );
        await connection.query('delete from users where id=@id',
            substitutionValues: {'id': user.id.toInt()});
      }
    });
    return Nothing();
  }

  @override
  Future<User> changePassword(ServiceCall call, User user) async {
    if (user.password.isEmpty) {
      throw GrpcError.invalidArgument('no new password');
    }
    if (call.clientMetadata==null || !call.clientMetadata!.containsKey('session')) {
      throw GrpcError.unauthenticated('no session in metadata');
    }
    User currentUser = await getUserBySession(Session()..cookie = call.clientMetadata!['session']!);
    String newPassword = makePasswordHash(user.password, user.id);
    await connection.query(
      'update users set password=@password where id=@id',
      substitutionValues: {
        'password': newPassword,
        'id': user.id.toInt(),
      }
    );
    return currentUser;
  }

  static String makePasswordHash(String password, dynamic salt) {
    String salted = '$password $salt)';
    String hexDigest = sha512.convert(utf8.encode(salted)).toString().toLowerCase();
    return hexDigest;
  }

  @override
  Future<User> createOrUpdateUser(ServiceCall? call, User user) async {
    User res;
    if (user.id > 0) {
      res = await getUserById(user.id);
    } else {
      res = User();
    }
    Map<String,dynamic> values = {};
    if (user.password.isNotEmpty && user.id == 0) {
      // allows to set password only at initial registration stage
      // use ResetUserPassword (by Admin role) or ChangePassword (by any Role) to set password
      values['password'] = '='+user.password;
      res.password = user.password;
    }
    if (user.login.isNotEmpty) {
      values['login'] = user.login;
      res.login = user.login;
    }
    if (user.firstName.isNotEmpty) {
      values['first_name'] = user.firstName;
      res.firstName = user.firstName;
    }
    if (user.lastName.isNotEmpty) {
      values['last_name'] = user.lastName;
      res.lastName = user.lastName;
    }
    if (user.midName.isNotEmpty) {
      values['mid_name'] = user.midName;
      res.midName = user.midName;
    }
    if (user.groupName.isNotEmpty) {
      values['group_name'] = user.groupName;
      res.groupName = user.groupName;
    }
    if (user.email.isNotEmpty) {
      values['email'] = user.email;
      res.email = user.email;
    }
    if (user.defaultRole != Role.ROLE_ANY) {
      values['default_role'] = user.defaultRole.value;
      res.defaultRole = user.defaultRole;
    }
    String sets = '';
    String placeholders = '';
    for (String key in values.keys) {
      if (sets.isNotEmpty) {
        sets += ', ';
        placeholders += ', ';
      }
      sets += '$key=@$key';
      placeholders += '@$key';
    }
    if (user.id > 0) {
      String query = 'update users set ' + sets + ' where id=' + user.id.toString();
      await connection.query(query, substitutionValues: values);
    } else {
      String query = 'insert into users(' + values.keys.join(', ') + ') values (' + placeholders + ') returning id';
      List<dynamic> row = await connection.query(query, substitutionValues: values);
      List<dynamic> fields = row.first;
      int id = fields.first;
      res.id = Int64(id);
      log.fine('created user ${user.email} with id = $id');
    }
    return res;
  }

  @override
  Future<Nothing> deleteUser(ServiceCall call, User user) async {
    if (user.id == 0) {
      throw GrpcError.invalidArgument('user id required');
    }
    await connection.query('delete from users where id=@id', substitutionValues: {'id': user.id.toInt()});
    return Nothing();
  }

  @override
  Future<User> getProfile(ServiceCall call, Session session) {
    return getUserBySession(session);
  }

  @override
  Future<UsersList> getUsers(ServiceCall call, UsersFilter filter) async {
    if (filter.user.id != 0) {
      User oneUser = await getUserById(filter.user.id);
      UsersList result = UsersList();
      result.users.add(oneUser);
      return result;
    }
    // todo find users enrolled to specific course
    String query = '''
    select 
      id,first_name,last_name,mid_name,group_name,email,default_role,disabled,login 
    from 
      users 
    order by 
      default_role desc,group_name,last_name,first_name
    ''';
    UsersList result = UsersList();
    List<dynamic> rows = await connection.query(query);
    for (List<dynamic> row in rows) {
      int id = row[0];
      String firstName = row[1] is String? row[1] : '';
      String lastName = row[2] is String? row[2] : '';
      String midName = row[3] is String? row[3] : '';
      String groupName = row[4] is String? row[4] : '';
      String email = row[5] is String? row[5] : '';
      Role role = Role.valueOf(row[6])!;
      bool disabled = row[7];
      String login = row[8] is String? row[8] : '';
      User user = User(
        id: Int64(id),
        firstName: firstName, lastName: lastName, midName: midName,
        groupName: groupName, password: '', email: email, disabled: disabled,
        defaultRole: role,
        login: login,
      );
      if (filter.role != Role.ROLE_ANY) {
        if (user.defaultRole != filter.role)
          continue;
      }
      bool partial = filter.partialStringMatch;
      if (!partialStringMatch(partial, user.firstName, filter.user.firstName))
        continue;
      if (!partialStringMatch(partial, user.lastName, filter.user.lastName))
        continue;
      if (!partialStringMatch(partial, user.midName, filter.user.midName))
        continue;
      if (!partialStringMatch(partial, user.email, filter.user.email))
        continue;
      if (!partialStringMatch(partial, user.groupName, filter.user.groupName))
        continue;
      if (!partialStringMatch(partial, user.login, filter.user.login))
        continue;
      if (!filter.includeDisabled && user.disabled)
        continue;
      result.users.add(user);
    }
    return result;
  }

  static bool partialStringMatch(bool partial, String candidate, String filter) {
    if (!partial && filter.isNotEmpty) {
      return candidate == filter;
    } else if (partial && filter.isNotEmpty) {
      String normalizedCandidate = candidate.toLowerCase().replaceAll('ё', 'е');
      String normalizedFilter = filter.toLowerCase().replaceAll('ё', 'е');
      return normalizedCandidate.contains(normalizedFilter);
    } else {
      return true;
    }
  }
  
  Future<User> getUserById(Int64 id) async {
    String query = '''
    select 
      first_name, last_name, mid_name, password, email, group_name, default_role, login 
    from users 
    where id=@id
    ''';
    List<dynamic> rows = await connection.query(query,
        substitutionValues: {'id': id.toInt()}
    );
    if (rows.isEmpty) {
      throw GrpcError.unauthenticated('user not found');
    }
    List<dynamic> fields = rows.first;
    String firstName = fields[0] is String ? fields[0] : '';
    String lastName = fields[1] is String ? fields[1] : '';
    String midName = fields[2] is String ? fields[2] : '';
    String password = fields[3];
    if (password.startsWith('=')) {
      password = password.substring(1);
    } else {
      password = '';
    }
    String email = fields[4] is String ? fields[4] : '';
    String groupName = fields[5] is String ? fields[5] : '';
    int roleI = fields[6];
    if (roleI == 0) {
      throw GrpcError.internal('User $id has no associated default role}');
    }
    Role role = Role.valueOf(roleI)!;
    String login = fields[7] is String ? fields[7] : '';
    return User(
      id: id,
      firstName: firstName, lastName: lastName, midName: midName,
      password: password, email: email, groupName: groupName, login: login,
      defaultRole: role,
    );
  }

  @override
  Future<User> resetUserPassword(ServiceCall call, User user) async {
    if (user.id==0 || user.password.isEmpty) {
      throw GrpcError.invalidArgument('user id and new password required');
    }
    String newPassword = '=' + user.password;
    await connection.query(
        'update users set password=@password where id=@id',
        substitutionValues: {
          'password': newPassword,
          'id': user.id.toInt(),
        }
    );
    return user;
  }

  @override
  Future<UserRole> setUserDefaultRole(ServiceCall call, UserRole arg) async {
    if (arg.user.id==0 && arg.user.email.isEmpty) {
      throw GrpcError.invalidArgument('bad user');
    }
    if (arg.user.id==0) {
      List<dynamic> rows = await connection.query(
        'select id from users where email=@email',
        substitutionValues: {'email': arg.user.email}
      );
      if (rows.isEmpty) {
        throw GrpcError.notFound('user not found');
      }
      List<dynamic> fields = rows.first;
      int id = fields.first;
      arg.user.id = Int64(id);
    }
    await connection.query(
      'update users set default_role=@role where id=@id',
      substitutionValues: {
        'role': arg.role.value,
        'id': arg.user.id.toInt()
      }
    );
    return arg;
  }

  Future<User> getUserBySession(Session session) async {
    Int64 userId = session.user.id;
    if (userId == 0) {
      List<dynamic> rows = await connection.query('select users_id from sessions where cookie=@cookie',
          substitutionValues: {'cookie': session.cookie});
      if (rows.isEmpty) {
        throw GrpcError.unauthenticated('session not found');
      }
      List<dynamic> firstRow = rows.first;
      userId = Int64(firstRow.first);
    }
    return getUserById(userId);
  }

  Future<Role> getDefaultRole(User user) async {
    List<dynamic> rows = await connection.query(
      'select default_role from users where id=@id',
      substitutionValues: {'id': user.id.toInt()}
    );
    return Role.valueOf(rows.first.first)!;
  }

  Future<User> getUserFromContext(ServiceCall call) {
    if (call.clientMetadata==null || !call.clientMetadata!.containsKey('session')) {
      throw GrpcError.unauthenticated('no session data in request metadata');
    }
    String sessionId = call.clientMetadata!['session']!;
    if (sessionId.isEmpty) {
      throw GrpcError.unauthenticated('session data is empty');
    }
    return getUserBySession(Session(cookie: sessionId));
  }

  @override
  Future<Session> startSession(ServiceCall call, Session request) async {
    User user = request.user;
    Session resultSession = request;
    dynamic getUserSessionError;
    String initialRoute = '/';
    try {
      user = await getUserBySession(request);
      if (user.defaultRole != Role.ROLE_ADMINISTRATOR) {
        final enrollmentsService = parent.enrollmentManagementService;
        final enrollmentsResponse = await enrollmentsService.getUserEnrollments(call, user);
        final enrollments = enrollmentsResponse.enrollments;
        if (enrollments.length == 1) {
          final singleEnrollment = enrollments.single;
          final course = singleEnrollment.course;
          final courseUrlPrefix = course.urlPrefix;
          initialRoute = '/' + courseUrlPrefix;
        }
        user = user.copyWith((u) { u.initialRoute = initialRoute; });
      }
      resultSession = resultSession.copyWith((s) {
        s.user = user;
      });
    }
    catch (e) {
      getUserSessionError = e;
    }

    bool forbidLogout = parent.demoModeProperties!=null && user.defaultRole!=Role.ROLE_ADMINISTRATOR;
    resultSession = resultSession.copyWith((s) {
      s.user = resultSession.user.copyWith((u) {
        u.forbidLogout = forbidLogout;
      });
    });

    if (getUserSessionError != null && parent.demoModeProperties == null) {
      throw getUserSessionError;
    }
    else if (getUserSessionError != null && parent.demoModeProperties != null) {
      // create temporary user for demo mode session
      User newUser = User(defaultRole: Role.ROLE_STUDENT, password: 'not_set');
      newUser = await createOrUpdateUser(call, newUser); // to assign real user id
      final newUserName = parent.demoModeProperties!.userNamePattern.replaceAll('%id', '${newUser.id}');
      newUser = newUser.copyWith((s) {
        s.login = newUserName;
      });
      user = await createOrUpdateUser(call, newUser);
      final courses = await parent.courseManagementService.getCourses(call, CoursesFilter());
      Course? course;
      final publicCourseUrlPrefix = parent.demoModeProperties!.publicCourse;
      for (final c in courses.courses) {
        if (c.course.urlPrefix == publicCourseUrlPrefix) {
          course = c.course;
          break;
        }
      }
      if (course != null) {
        final enroll = EnrollUserRequest(
          course: course,
          user: user,
          role: Role.ROLE_STUDENT,
        );
        await parent.enrollmentManagementService.enrollUser(call, enroll);
        initialRoute = '/' + parent.demoModeProperties!.publicCourse;
      }
      user = user.copyWith((u) {
        u.initialRoute = initialRoute;
        u.forbidLogout = false;
      });
      resultSession = await createSessionForAuthenticatedUser(user);
      log.fine('successfully created new demo user ${user.login} with session ${resultSession.cookie}');
    }

    return resultSession;
  }



}