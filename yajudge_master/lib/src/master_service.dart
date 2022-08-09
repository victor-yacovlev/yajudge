import 'dart:async';
import 'dart:core';
import 'dart:io' as io;
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:postgres/postgres.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:path/path.dart';
import 'course_management.dart';
import 'deadlines_manager.dart';
import 'submission_management.dart';
import 'user_management.dart';
import 'enrollment_management.dart';
import 'code_review_management.dart';

const notLoggedMethods = ['StartSession', 'Authorize'];
const privateMethods = [
  'TakeSubmissionToGrade', 'GetProblemFullContent', 'UpdateGraderOutput',
  'ReceiveSubmissionsToProcess', 'SetExternalServiceStatus',
];
const studentsMethods = [
  'GetProfile', 'ChangePassword',
  'GetCourses', 'GetCoursePublicContent',
  'CheckSubmissionsCountLimit', 'SubmitProblemSolution', 'GetSubmissions',
  'CheckCourseStatus', 'CheckProblemStatus', 'GetSubmissionResult',
  'SubscribeToProblemStatusNotifications',
  'SubscribeToCourseStatusNotifications',
  'SubscribeToSubmissionResultNotifications',
  'GetReviewHistory', 'GetLessonSchedules',
];

const maxErrorsPerMinute = 3;
const restartTimeoutSecs = 1;

class MasterService {
  final Logger log = Logger('MasterService');
  int _errorsLastMinute = 0;
  final PostgreSQLConnection connection;
  final Db? storageDb;
  final RpcProperties rpcProperties;
  final MasterLocationProperties locationProperties;
  late final UserManagementService userManagementService;
  late final CourseManagementService courseManagementService;
  late final SubmissionManagementService submissionManagementService;
  late final EnrollmentManagementService enrollmentManagementService;
  late final CodeReviewManagementService codeReviewManagementService;
  late final DeadlinesManager deadlinesManager;
  final lastSessionClientSeen = <String,DateTime>{};

  final grpcServices = <String,Service>{};
  final grpcServers = <Server>[];
  final DemoModeProperties? demoModeProperties;

  MasterService({
    required this.connection,
    this.storageDb,
    required this.rpcProperties,
    required this.locationProperties,
    this.demoModeProperties,
  })
  {
    userManagementService = UserManagementService(parent: this, connection: connection);
    String coursesRoot = normalize(absolute(locationProperties.coursesRoot));
    String problemsRoot = normalize(absolute(locationProperties.problemsRoot));
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
      connection: connection,
      storageDb: storageDb,
    );
    enrollmentManagementService = EnrollmentManagementService(
      parent: this,
      connection: connection,
    );
    codeReviewManagementService = CodeReviewManagementService(
      parent: this,
      connection: connection,
    );
    grpcServices[userManagementService.$name] = userManagementService;
    grpcServices[courseManagementService.$name] = courseManagementService;
    grpcServices[submissionManagementService.$name] = submissionManagementService;
    grpcServices[enrollmentManagementService.$name] = enrollmentManagementService;
    grpcServices[codeReviewManagementService.$name] = codeReviewManagementService;
    deadlinesManager = DeadlinesManager(this, connection);
    io.ProcessSignal.sigterm.watch().listen((_) => shutdown('SIGTERM'));
    io.ProcessSignal.sigint.watch().listen((_) => shutdown('SIGINT'));
    deadlinesManager.start();
  }

  FutureOr<GrpcError?> checkAuth(ServiceCall call, ServiceMethod method) async {
    if (notLoggedMethods.contains(method.name)) {
      return null;
    }
    if (privateMethods.contains(method.name)) {
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
    User currentUser;
    try {
      currentUser = await userManagementService.getUserBySession(session);
    }
    catch (error) {
      if (error is GrpcError) {
        return error;
      }
      else {
        rethrow;
      }
    }
    if (currentUser.defaultRole == Role.ROLE_STUDENT) {
      if (!studentsMethods.contains(method.name)) {
        return GrpcError.permissionDenied('not allowed for method ${method.name}');
      }
    }
    lastSessionClientSeen[session.cookie] = DateTime.now();
    return null;
  }

  Future<void> serve() async {
    final interceptors = [checkAuth];
    final servers = <Endpoint,List<Service>>{};
    for (final endpointEntry in rpcProperties.endpoints.entries) {
      Endpoint endpoint = endpointEntry.value;
      final serviceName = endpointEntry.key;
      List<Service> serverServices = [];
      for (final existingEntry in servers.entries) {
        final existingEndpoint = existingEntry.key;
        if (existingEndpoint.connectionEquals(endpoint)) {
          serverServices = existingEntry.value;
          endpoint = existingEndpoint;
          break;
        }
      }
      if (grpcServices.containsKey(serviceName)) {
        serverServices.add(grpcServices[serviceName]!);
      }
      servers[endpoint] = serverServices;
    }
    for (final serverEntry in servers.entries) {
      final endpoint = serverEntry.key;
      final services = serverEntry.value;
      final serviceNames = services.map((e) => e.$name);
      log.info('listening services $serviceNames on $endpoint');
      final grpcServer = Server(services, interceptors);
      dynamic address;
      if (!endpoint.isUnix) {
        if (endpoint.host.isEmpty) {
          address = InternetAddress.anyIPv4;
        }
        else {
          address = endpoint.host;
        }
        grpcServer.serve(address: address, port: endpoint.port, shared: true);
      }
      else {
        address = InternetAddress(endpoint.unixPath, type: io.InternetAddressType.unix);
        grpcServer.serve(address: address, shared: true);
      }
      grpcServers.add(grpcServer);
    }
  }

  void handleServingError(Object? error, StackTrace stackTrace) {
    String stackTraceLine = stackTrace.toString().replaceAll('\n', ' ');
    log.severe('$error [$stackTraceLine]');
    _errorsLastMinute += 1;
    if (_errorsLastMinute >= maxErrorsPerMinute) {
      log.shout('too many errors withing one minute');
      shutdown('too many errors', true);
    }
    Future.delayed(Duration(seconds: restartTimeoutSecs))
        .then((_) => serveSupervised());
  }

  void serveSupervised() {
    runZonedGuarded(() async {
      await serve();
    }, (e,s) => handleServingError(e,s));
  }

  void shutdown(String reason, [bool error = false]) async {
    log.info('shutting down due to $reason');
    for (final grpcServer in grpcServers) {
      grpcServer.shutdown();
    }
    io.sleep(Duration(seconds: 2));
    log.info('shutdown');
    io.exit(error? 1 : 0);
  }

}