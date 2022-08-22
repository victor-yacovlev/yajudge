import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:yajudge_common/yajudge_common.dart';

import '../service_call_extension.dart';


class UserManagementService extends UserManagementServiceBase {

  final PostgreSQLConnection dbConnection;
  final log = Logger('UsersManager');
  final String secretKey;

  UserManagementService({required this.dbConnection, required this.secretKey}): super();



  @override
  Future<UsersList> batchCreateStudents(ServiceCall call, UsersList request) async {
    for (User user in request.users) {
      user.password = generateRandomPassword();
      user.defaultRole = Role.ROLE_STUDENT;
      user = await createOrUpdateUser(call, user);
    }
    return request;
  }


  @override
  Future<Nothing> batchDeleteUsers(ServiceCall call, UsersList request) async {
    if (request.users.isEmpty) {
      return Nothing();
    }
    await dbConnection.transaction((connection) async {
      for (User user in request.users) {
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
  Future<User> changePassword(ServiceCall call, User request) async {
    if (request.password.isEmpty) {
      throw GrpcError.invalidArgument('no new password');
    }
    User? currentUser = call.getSessionUser(secretKey);
    if (currentUser == null) {
      throw GrpcError.unauthenticated('not authorized');
    }
    String newPassword = makePasswordHash(request.password, request.id);
    await dbConnection.query(
      'update users set password=@password where id=@id',
      substitutionValues: {
        'password': newPassword,
        'id': request.id.toInt(),
      }
    );
    return currentUser;
  }

  @override
  Future<User> createOrUpdateUser(ServiceCall? call, User request) async {
    User res;
    if (request.id > 0) {
      res = await getProfileById(call, request);
    } else {
      res = User();
    }
    Map<String,dynamic> values = {};
    if (request.password.isNotEmpty && request.id == 0) {
      // allows to set password only at initial registration stage
      // use ResetUserPassword (by Admin role) or ChangePassword (by any Role) to set password
      values['password'] = '=${request.password}';
      res.password = request.password;
    }
    if (request.login.isNotEmpty) {
      values['login'] = request.login;
      res.login = request.login;
    }
    if (request.firstName.isNotEmpty) {
      values['first_name'] = request.firstName;
      res.firstName = request.firstName;
    }
    if (request.lastName.isNotEmpty) {
      values['last_name'] = request.lastName;
      res.lastName = request.lastName;
    }
    if (request.midName.isNotEmpty) {
      values['mid_name'] = request.midName;
      res.midName = request.midName;
    }
    if (request.groupName.isNotEmpty) {
      values['group_name'] = request.groupName;
      res.groupName = request.groupName;
    }
    if (request.email.isNotEmpty) {
      values['email'] = request.email;
      res.email = request.email;
    }
    if (request.defaultRole != Role.ROLE_ANY) {
      values['default_role'] = request.defaultRole.value;
      res.defaultRole = request.defaultRole;
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
    if (request.id > 0) {
      String query = 'update users set $sets where id=${request.id}';
      await dbConnection.query(query, substitutionValues: values);
    } else {
      String query = 'insert into users(${values.keys.join(', ')}) values ($placeholders) returning id';
      List<dynamic> row = await dbConnection.query(query, substitutionValues: values);
      List<dynamic> fields = row.first;
      int id = fields.first;
      res.id = Int64(id);
      log.fine('created user ${request.email} with id = $id');
    }
    return res;
  }

  @override
  Future<Nothing> deleteUser(ServiceCall call, User request) async {
    if (request.id == 0) {
      throw GrpcError.invalidArgument('user id required');
    }
    await dbConnection.query('delete from users where id=@id', substitutionValues: {'id': request.id.toInt()});
    return Nothing();
  }

    @override
  Future<UsersList> getUsers(ServiceCall call, UsersFilter request) async {
    if (request.user.id != 0) {
      User oneUser = await getProfileById(call, request.user);
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
    List<dynamic> rows = await dbConnection.query(query);
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
      if (request.role != Role.ROLE_ANY) {
        if (user.defaultRole != request.role) {
          continue;
        }
      }
      bool partial = request.partialStringMatch;
      if (!partialStringMatch(partial, user.firstName, request.user.firstName)) {
        continue;
      }
      if (!partialStringMatch(partial, user.lastName, request.user.lastName)) {
        continue;
      }
      if (!partialStringMatch(partial, user.midName, request.user.midName)) {
        continue;
      }
      if (!partialStringMatch(partial, user.email, request.user.email)) {
        continue;
      }
      if (!partialStringMatch(partial, user.groupName, request.user.groupName)) {
        continue;
      }
      if (!partialStringMatch(partial, user.login, request.user.login)) {
        continue;
      }
      if (!request.includeDisabled && user.disabled) {
        continue;
      }
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

  @override
  Future<User> resetUserPassword(ServiceCall call, User request) async {
    if (request.id==0 || request.password.isEmpty) {
      throw GrpcError.invalidArgument('user id and new password required');
    }
    String newPassword = '=${request.password}';
    await dbConnection.query(
        'update users set password=@password where id=@id',
        substitutionValues: {
          'password': newPassword,
          'id': request.id.toInt(),
        }
    );
    return request;
  }

  @override
  Future<UserRole> setUserDefaultRole(ServiceCall call, UserRole request) async {
    if (request.user.id==0 && request.user.email.isEmpty) {
      throw GrpcError.invalidArgument('bad user');
    }
    if (request.user.id==0) {
      List<dynamic> rows = await dbConnection.query(
        'select id from users where email=@email',
        substitutionValues: {'email': request.user.email}
      );
      if (rows.isEmpty) {
        throw GrpcError.notFound('user not found');
      }
      List<dynamic> fields = rows.first;
      int id = fields.first;
      request.user.id = Int64(id);
    }
    await dbConnection.query(
      'update users set default_role=@role where id=@id',
      substitutionValues: {
        'role': request.role.value,
        'id': request.user.id.toInt()
      }
    );
    return request;
  }

  // Future<User> getUserBySession(Session session) async {
  //   Int64 userId = session.user.id;
  //   if (userId == 0) {
  //     List<dynamic> rows = await dbConnection.query('select users_id from sessions where cookie=@cookie',
  //         substitutionValues: {'cookie': session.cookie});
  //     if (rows.isEmpty) {
  //       throw GrpcError.unauthenticated('session not found');
  //     }
  //     List<dynamic> firstRow = rows.first;
  //     userId = Int64(firstRow.first);
  //   }
  //   return getUserById(userId);
  // }

  Future<Role> getDefaultRole(User user) async {
    List<dynamic> rows = await dbConnection.query(
      'select default_role from users where id=@id',
      substitutionValues: {'id': user.id.toInt()}
    );
    return Role.valueOf(rows.first.first)!;
  }

  // Future<User> getUserFromContext(ServiceCall call) {
  //   if (call.clientMetadata==null || !call.clientMetadata!.containsKey('session')) {
  //     throw GrpcError.unauthenticated('no session data in request metadata');
  //   }
  //   String sessionId = call.clientMetadata!['session']!;
  //   if (sessionId.isEmpty) {
  //     throw GrpcError.unauthenticated('session data is empty');
  //   }
  //   return getUserBySession(Session(cookie: sessionId));
  // }

  @override
  Future<User> getProfileById(ServiceCall? call, User request) async {
    String query = '''
    select 
      first_name, last_name, mid_name, password, email, group_name, default_role, login 
    from users 
    where id=@id
    ''';
    List<dynamic> rows = await dbConnection.query(query,
        substitutionValues: {'id': request.id.toInt()}
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
      throw GrpcError.internal('User ${request.id} has no associated default role}');
    }
    Role role = Role.valueOf(roleI)!;
    String login = fields[7] is String ? fields[7] : '';
    return User(
      id: request.id,
      firstName: firstName, lastName: lastName, midName: midName,
      password: password, email: email, groupName: groupName, login: login,
      defaultRole: role,
    );
  }

}