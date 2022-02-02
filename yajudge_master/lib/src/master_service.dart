import 'dart:async';
import 'dart:core';
import 'dart:io' as io;
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:path/path.dart';
import './course_management.dart';
import './submission_management.dart';
import './user_management.dart';

const NotLoggedMethods = ['Authorize'];
const PrivateMethods = [
  'TakeSubmissionToGrade', 'GetProblemFullContent', 'UpdateGraderOutput',
];
const StudentsMethods = [
  'GetProfile', 'ChangePassword',
  'GetCourses', 'GetCoursePublicContent',
  'CheckSubmissionsCountLimit', 'SubmitProblemSolution', 'GetSubmissions'
];

const MaxErrorsPerMinute = 3;
const RestartTimeoutSecs = 1;

class MasterService {
  final Logger log = Logger('MasterService');
  int _errorsLastMinute = 0;
  late final Timer _errorsResetTimer;
  final PostgreSQLConnection connection;
  final RpcProperties rpcProperties;
  final MasterLocationProperties locationProperties;
  late final UserManagementService userManagementService;
  late final CourseManagementService courseManagementService;
  late final SubmissionManagementService submissionManagementService;
  late final Server grpcServer;

  MasterService({
    required this.connection,
    required this.rpcProperties,
    required this.locationProperties,
  })
  {
    _errorsResetTimer = Timer.periodic(Duration(minutes: 1), (timer) {
      _errorsLastMinute = 0;
    });
    userManagementService = UserManagementService(connection: connection);
    String coursesRoot = normalize(absolute(this.locationProperties.coursesRoot));
    String problemsRoot = normalize(absolute(this.locationProperties.problemsRoot));
    log.info('using courses root $coursesRoot');
    log.info('using problems root $problemsRoot');
    if (!io.Directory(coursesRoot).existsSync()) {
      throw Exception('Courses root directory does not exists: $coursesRoot');
    }
    courseManagementService = CourseManagementService(
      parent: this,
      connection: connection,
      locationProperties: locationProperties,
    );
    submissionManagementService = SubmissionManagementService(
        parent: this,
        connection: connection
    );
    grpcServer = Server(
        [userManagementService, courseManagementService, submissionManagementService],
        [checkAuth]
    );
    io.ProcessSignal.sigterm.watch().listen((_) => shutdown('SIGTERM'));
    io.ProcessSignal.sigint.watch().listen((_) => shutdown('SIGINT'));
  }

  FutureOr<GrpcError?> checkAuth(ServiceCall call, ServiceMethod method) async {
    if (NotLoggedMethods.contains(method.name)) {
      return null;
    }
    if (PrivateMethods.contains(method.name)) {
      String? auth = call.clientMetadata!.containsKey('token') ? call.clientMetadata!['token'] : null;
      if (auth == null) {
        return GrpcError.unauthenticated('no token metadata to access private method ${method.name}');
      }
      if (auth != rpcProperties.privateToken) {
        return GrpcError.unauthenticated('cant access private method ${method.name}');
      }
      return null;
    }
    String? sessionId = call.clientMetadata!.containsKey('session') ? call.clientMetadata!['session'] : null;
    if (sessionId == null) {
      return GrpcError.unauthenticated('no session metadata to access ${method.name}');
    }
    Session session = Session();
    session.cookie = sessionId;
    User currentUser = await userManagementService.getUserBySession(session);
    if (currentUser.defaultRole == Role.ROLE_STUDENT) {
      if (!StudentsMethods.contains(method.name)) {
        return GrpcError.permissionDenied('not allowed for method ${method.name}');
      }
    }
    return null;
  }

  Future<void> serve() {
    log.info('listening master on ${rpcProperties.host}:${rpcProperties.port}');
    dynamic address;
    if (rpcProperties.host=='*' || rpcProperties.host=='any') {
      address = InternetAddress.anyIPv4;
    } else {
      address = rpcProperties.host;
    }
    return grpcServer.serve(
      address: address,
      port: rpcProperties.port,
      shared: true,
    );
  }

  void handleServingError(Object? error, StackTrace stackTrace) {
    String stackTraceLine = stackTrace.toString().replaceAll('\n', ' ');
    log.severe('$error [$stackTraceLine]');
    _errorsLastMinute += 1;
    if (_errorsLastMinute >= MaxErrorsPerMinute) {
      log.shout('too many errors withing one minute');
      shutdown('too many errors', true);
    }
    Future.delayed(Duration(seconds: RestartTimeoutSecs))
        .then((_) => serveSupervised());
  }

  void serveSupervised() {
    runZonedGuarded(() async {
      await serve();
    }, (e,s) => handleServingError(e,s));
  }

  void shutdown(String reason, [bool error = false]) async {
    log.info('shutting down due to $reason');
    await grpcServer.shutdown();
    log.info('shutdown');
    io.exit(error? 1 : 0);
  }

}