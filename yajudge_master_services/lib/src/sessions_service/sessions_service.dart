import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:protobuf/protobuf.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:fixnum/fixnum.dart';
import '../service_call_extension.dart';


class SessionManagementService extends SessionManagementServiceBase {

  final PostgreSQLConnection dbConnection;
  final log = Logger('UsersManager');
  final UserManagementClient usersManager;
  final CourseManagementClient coursesManager;
  final String secretKey;

  SessionManagementService({
    required this.dbConnection,
    required this.coursesManager,
    required this.usersManager,
    required this.secretKey,
  }): super();

  @override
  Future<Session> authorize(ServiceCall call, User request) async {
    if (request.id==0 && request.email.isEmpty && request.login.isEmpty) {
      log.warning('empty user id tried to authorize');
      throw GrpcError.invalidArgument('id or email not provided');
    }
    if (request.password.isEmpty) {
      log.warning('user ${request.id} / ${request.email} tried to authorize with no password');
      throw GrpcError.invalidArgument('password not provided');
    }
    if (request.disabled) {
      log.warning('disabled user ${request.id} / ${request.email} tried to authorize');
      throw GrpcError.permissionDenied('user disabled');
    }
    String findByIdQuery = 'select id, password from users where id=@id';
    String findByEmailQuery = 'select id, password from users where email=@email';
    String findByLoginQuery = 'select id, password from users where login=@login';
    List<List<dynamic>> usersRows;
    if (request.id > 0) {
      usersRows = await dbConnection.query(
          findByIdQuery, substitutionValues: {'id': request.id.toInt()}
      );
    } else if (request.email.isNotEmpty) {
      usersRows = await dbConnection.query(
          findByEmailQuery, substitutionValues: {'email': request.email}
      );
    } else {
      usersRows = await dbConnection.query(
          findByLoginQuery, substitutionValues: {'login': request.login}
      );
    }
    if (usersRows.isEmpty) {
      log.warning('not existing user ${request.id} / ${request.email} tried to authorize');
      throw GrpcError.notFound('user not found');
    }
    List<dynamic> singleUserRow = usersRows.single;
    int userId = singleUserRow[0];
    String userPassword = singleUserRow[1];
    bool passwordMatch;
    if (userPassword.startsWith('=')) {
      // plain text password
      passwordMatch = request.password == userPassword.substring(1);
    } else {
      String hexDigest = makePasswordHash(request.password, Int64(userId));
      passwordMatch = userPassword == hexDigest;
    }
    if (!passwordMatch) {
      log.warning('user ${request.id} / ${request.email} tried to authorize with wrong password');
      throw GrpcError.permissionDenied('wrong password');
    }
    request.id = Int64(userId);
    final session = await createSessionForAuthenticatedUser(call, request, "/");
    log.fine('user ${request.id} / ${request.email} successfully authorized');
    return session;
  }

  @override
  Future<Session> startSession(ServiceCall call, Session request) async {
    Session resultSession = request.deepCopy();
    String initialRoute = '/';
    User user = await getUserIdAndRole(call, request);
    user = await usersManager.getProfileById(user,
      options: CallOptions(metadata: call.clientMetadata!..putIfAbsent('session', () => resultSession.cookie)),
    );

    if (user.defaultRole != Role.ROLE_ADMINISTRATOR) {
      final enrollmentsResponse = await coursesManager.getUserEnrollments(
        user,
        options: CallOptions(metadata: call.clientMetadata!..putIfAbsent('session', () => resultSession.cookie)),
      );
      final enrollments = enrollmentsResponse.enrollments;
      if (enrollments.length == 1) {
        final singleEnrollment = enrollments.single;
        final course = singleEnrollment.course;
        final courseUrlPrefix = course.urlPrefix;
        initialRoute = '/$courseUrlPrefix';
      }
    }
    resultSession.user = user;
    resultSession.initialRoute = initialRoute;
    resultSession.userEncryptedData = user.toEncryptedBase64(secretKey);
    return resultSession;
  }

  Future<Session> createSessionForAuthenticatedUser(ServiceCall call, User user, String initialRoute) async {
    DateTime timestamp = DateTime.now();
    String sessionKey = '${user.id} ${user.email} ${timestamp.millisecondsSinceEpoch}';
    sessionKey = sha256.convert(utf8.encode(sessionKey)).toString();
    call.session = sessionKey;
    final userProfile = await usersManager.getProfileById(user,
      options: CallOptions(metadata: {'session': sessionKey}),
    );
    Session session = Session(
      cookie: sessionKey,
      start: Int64(timestamp.millisecondsSinceEpoch ~/ 1000),
      user: userProfile,
      initialRoute: initialRoute.isEmpty? "/" : initialRoute,
      userEncryptedData: user.toEncryptedBase64(secretKey),
    );
    // try to find existing session first
    List<dynamic> existingSessionsRows = await dbConnection.query(
      'select cookie from sessions where cookie=@c',
      substitutionValues: { 'c': sessionKey },
    );
    if (existingSessionsRows.isEmpty) {
      // create new session if not found
      String storeSessionQuery = 'insert into sessions(cookie, users_id, start) values (@c, @id, @st)';
      await dbConnection.query(storeSessionQuery, substitutionValues: {
        'c': sessionKey, 'id': user.id.toInt(), 'st': timestamp
      });
    }
    return session;
  }

  @override
  Future<User> getUserIdAndRole(ServiceCall call, Session request) async {
    final userIdQuery = 'select users_id from sessions where cookie=@c';
    final userRows = await dbConnection.query(userIdQuery, substitutionValues: {'c': request.cookie});
    if (userRows.isEmpty) {
      throw GrpcError.unauthenticated('session not found');
    }
    final userId = userRows.first.single as int;
    final userRoleQuery = 'select default_role from users where id=@id';
    final roleRows = await dbConnection.query(userRoleQuery, substitutionValues: {'id': userId});
    if (roleRows.isEmpty) {
      throw GrpcError.notFound('user associated to session not found');
    }
    final roleNumber = roleRows.first.single as int;
    final role = Role.valueOf(roleNumber) ?? Role.ROLE_STUDENT;
    return User(id: Int64(userId), defaultRole: role);
  }

}
