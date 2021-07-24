import 'package:yajudge_client/wsapi/courses.dart';

import 'connection.dart';
import 'package:json_annotation/json_annotation.dart';

part 'users.g.dart';

const UserRole_Any = 0;
const UserRole_Unauthorized = 1;
const UserRole_Student = 2;
const UserRole_TeacherAssistant = 3;
const UserRole_Teacher = 4;
const UserRole_Lecturer = 5;
const UserRole_Administrator = 6;

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class User {
  int id = 0;
  String? firstName;
  String? lastName;
  String? midName;
  String? email;
  String? groupName;
  String? password;
  int? defaultRole;
  bool? disabled = false;

  User();
  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);

  String fullName() {
    String result = '';
    if (lastName != null) {
      result += lastName!;
    }
    if (firstName != null) {
      if (result.isNotEmpty) {
        result += ' ';
      }
      result += firstName!;
    }
    if (midName != null) {
      if (result.isNotEmpty) {
        result += ' ';
      }
      result += midName!;
    }
    return result;
  }
}

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class Session {
  String cookie = '';
  int userId = 0;
  int start = 0;

  Session();
  factory Session.fromJson(Map<String, dynamic> json) =>
      _$SessionFromJson(json);
  Map<String, dynamic> toJson() => _$SessionToJson(this);
}

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class UsersFilter {
  int role = UserRole_Any;
  User? user;
  Course? course;
  bool partialStringMatch = true;
  bool includeDisabled = true;

  UsersFilter();
  factory UsersFilter.fromJson(Map<String, dynamic> json) =>
      _$UsersFilterFromJson(json);
  Map<String, dynamic> toJson() => _$UsersFilterToJson(this);
}

@JsonSerializable(includeIfNull: true, fieldRename: FieldRename.snake)
class UsersList {
  // List<Users> in fact. Json annotation library can't handle List<T>
  List<dynamic> users = List.empty(growable: true);

  UsersList();
  factory UsersList.fromJson(Map<String, dynamic> json) {
    var userListEntry = json['users'];
    List<User> ulist = List.empty(growable: true);
    for (var entry in userListEntry) {
      User user = User.fromJson(entry);
      ulist.add(user);
    }
    return UsersList()..users = ulist;
  }
  Map<String, dynamic> toJson() => _$UsersListToJson(this);
}

class UsersService extends ServiceBase {
  static UsersService? _instance;

  UsersService(RpcConnection connection) : super('UserManagement', connection) {
    if (UsersService._instance == null) {
      UsersService._instance = this;
    }
  }

  static UsersService get instance {
    assert (_instance != null);
    return UsersService._instance!;
  }

  Future<Session> authorize(User user) async {
    Future res = callUnaryMethod('Authorize', user);
    try {
      var dataJson = await res;
      Session session = Session.fromJson(dataJson);
      return session;
    } catch (err) {
      return Future.error(err);
    }
  }

  Future<User> getProfile(Session session) async {
    Future res = callUnaryMethod('GetProfile', session);
    try {
      var dataJson = await res;
      User user = User.fromJson(dataJson);
      return user;
    } catch (err) {
      return Future.error(err);
    }
  }

  Future<UsersList> getUsers(UsersFilter filter) async {
    Future res = callUnaryMethod('GetUsers', filter);
    try {
      var dataJson = await res;
      UsersList list = UsersList.fromJson(dataJson);
      return list;
    } catch (err) {
      return Future.error(err);
    }
  }

  Future<UsersList> batchCreateStudents(UsersList src) async {
    Future res = callUnaryMethod('BatchCreateStudents', src);
    try {
      var dataJson = await res;
      UsersList list = UsersList.fromJson(dataJson);
      return list;
    } catch (err) {
      return Future.error(err);
    }
  }

  Future<void> batchDeleteUsers(UsersList src) async {
    Future res = callUnaryMethod('BatchDeleteUsers', src);
    try {
      var _ = await res;
    } catch (err) {
      return Future.error(err);
    }
  }

  Future<User> resetUserPassword(User user) async {
    Future res = callUnaryMethod('ResetUserPassword', user);
    try {
      var dataJson = await res;
      User changedUser = User.fromJson(dataJson);
      return changedUser;
    } catch (err) {
      return Future.error(err);
    }
  }

  Future<User> changePassword(User user) async {
    Future res = callUnaryMethod('ChangePassword', user);
    try {
      var dataJson = await res;
      User changedUser = User.fromJson(dataJson);
      return changedUser;
    } catch (err) {
      return Future.error(err);
    }
  }

  Future<User> createOrUpdateUser(User user) async {
    Future res = callUnaryMethod('CreateOrUpdateUser', user);
    try {
      var dataJson = await res;
      User changedUser = User.fromJson(dataJson);
      return changedUser;
    } catch (err) {
      return Future.error(err);
    }
  }

}
