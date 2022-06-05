import 'package:grpc/grpc.dart';
import 'package:grpc/grpc_connection_interface.dart';
import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import '../utils/utils.dart';
import 'courses_controller.dart';

class AuthGrpcInterceptor implements ClientInterceptor {
  String sessionCookie = '';

  @override
  ResponseStream<R> interceptStreaming<Q, R>(
      ClientMethod<Q, R> method,
      Stream<Q> requests,
      CallOptions options,
      ClientStreamingInvoker<Q, R> invoker) {
    CallOptions newOptions = options.mergedWith(CallOptions(metadata: {'session': sessionCookie}));
    return invoker(method, requests, newOptions);
  }

  @override
  ResponseFuture<R> interceptUnary<Q, R>(ClientMethod<Q, R> method, Q request,
      CallOptions options, ClientUnaryInvoker<Q, R> invoker) {
    CallOptions newOptions = options.mergedWith(CallOptions(metadata: {'session': sessionCookie}));
    return invoker(method, request, newOptions);
  }
}

class ConnectionController {

  static ConnectionController? instance;
  final log = Logger('ConnectionController');

  ClientChannelBase? _clientChannel;
  final _authGrpcInterceptor = AuthGrpcInterceptor();
  late UserManagementClient usersService;
  late CourseManagementClient coursesService;
  late SubmissionManagementClient submissionsService;
  late EnrollmentsManagerClient enrollmentsService;
  late CodeReviewManagementClient codeReviewService;
  late final Uri _connectionUri;

  Session _session = Session();

  ConnectionController(this._connectionUri) {

    if (_clientChannel != null) {
      _clientChannel!.shutdown();
    }
    final host = _connectionUri.host;
    final secure = ['grpcs', 'https'].contains(_connectionUri.scheme);
    int port = _connectionUri.port;
    if (port == 0) {
      port = secure ? 443 : 80;
    }

    _clientChannel = GrpcOrGrpcWebClientChannel.toSingleEndpoint(
        host: host,
        port: port,
        transportSecure: secure,
    );

    if (host == 'localhost') {
      Logger.root.level = Level.ALL;
      Logger.root.info('log level changed to ${Logger.root.level.name}');
    }
    log.fine('created client channel to host $host');

    usersService = UserManagementClient(
      _clientChannel!,
      interceptors: [_authGrpcInterceptor],
    );

    coursesService = CourseManagementClient(
      _clientChannel!,
      interceptors: [_authGrpcInterceptor],
    );

    submissionsService = SubmissionManagementClient(
      _clientChannel!,
      interceptors: [_authGrpcInterceptor],
    );

    enrollmentsService = EnrollmentsManagerClient(
      _clientChannel!,
      interceptors: [_authGrpcInterceptor],
    );

    codeReviewService = CodeReviewManagementClient(
      _clientChannel!,
      interceptors: [_authGrpcInterceptor],
    );

    String sessionId = sessionCookie;
    _authGrpcInterceptor.sessionCookie = sessionId;

    log.fine('set initial sessionId = $sessionId');
  }

  Uri get connectionUri => _connectionUri;

  static void initialize(Uri connectionUri) {
    if (instance==null || instance!._connectionUri != connectionUri) {
      instance = ConnectionController(connectionUri);
      CoursesController.initialize();
    }
  }

  Future<Session> getSession() async {
    if (_session.cookie.isNotEmpty && _session.user.id!=0) {
      return _session;
    }
    try {
      _session = await usersService.startSession(Session(cookie: sessionCookie));
      sessionCookie = _session.cookie;
      return _session;
    }
    catch (e) {
      return Session();
    }
  }

  void setSession(Session session) {
    _session = session;
    sessionCookie = session.cookie;
  }

  String get sessionCookie {
    String? settingsValue = PlatformsUtils.getInstance().loadSettingsValue('session');
    if (settingsValue == null) {
      log.info('has no session key in application settings');
    }
    else {
      log.fine('got session key from application settings: $settingsValue');
    }
    return settingsValue!=null? settingsValue : '';
  }

  set sessionCookie(String newValue) {
    PlatformsUtils.getInstance().saveSettingsValue('session', newValue);
    _authGrpcInterceptor.sessionCookie = newValue;
    log.fine('saved session key to application settings: $newValue');
  }

}