import 'package:grpc/grpc.dart';
import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import '../utils/utils.dart';
import 'course_content_controller.dart';

class AuthGrpcInterceptor implements ClientInterceptor {
  String sessionCookie = '';
  String sessionUserEncrypted = '';

  @override
  ResponseStream<R> interceptStreaming<Q, R>(
      ClientMethod<Q, R> method,
      Stream<Q> requests,
      CallOptions options,
      ClientStreamingInvoker<Q, R> invoker) {
    CallOptions newOptions = options.mergedWith(CallOptions(metadata: _createMetadata()));
    return invoker(method, requests, newOptions);
  }

  @override
  ResponseFuture<R> interceptUnary<Q, R>(ClientMethod<Q, R> method, Q request,
      CallOptions options, ClientUnaryInvoker<Q, R> invoker) {
    CallOptions newOptions = options.mergedWith(CallOptions(metadata: _createMetadata()));
    return invoker(method, request, newOptions);
  }

  Map<String,String> _createMetadata() {
    final metadata = <String,String>{};
    metadata['session'] = sessionCookie;
    metadata['session_user'] = sessionUserEncrypted;
    return metadata;
  }
}

class ConnectionController {

  static ConnectionController? instance;
  final log = Logger('ConnectionController');
  late final RpcProperties rpcProperties;
  final _authGrpcInterceptor = AuthGrpcInterceptor();
  late UserManagementClient usersService;
  late SessionManagementClient sessionsService;
  late CourseManagementClient coursesService;
  late CourseContentProviderClient contentService;
  late DeadlinesManagementClient deadlinesService;
  late SubmissionManagementClient submissionsService;
  late CodeReviewManagementClient codeReviewService;
  late ProgressCalculatorClient progressService;
  late final Uri _connectionUri;
  final Map<String,dynamic> _clientChannels = {};

  Session _session = Session();

  ConnectionController(this._connectionUri) {
    final scheme = _connectionUri.scheme;
    if (['http', 'https'].contains(scheme)) {
      rpcProperties = RpcProperties.fromSingleEndpoint(_connectionUri);
    }
    else if ('endpoints' == scheme) {
      rpcProperties = RpcProperties.fromEndpointsFile(_connectionUri);
    }
    else if (_connectionUri.scheme.isEmpty && _connectionUri.path.isEmpty) {
      return;
    }
    else {
      throw ArgumentError('must be http://, https:// or endpoints:// scheme');
    }

    usersService = UserManagementClient(
      _createClientChannel('yajudge.UserManagement'),
      interceptors: [_authGrpcInterceptor],
    );

    sessionsService = SessionManagementClient(
      _createClientChannel('yajudge.SessionManagement'),
      interceptors: [_authGrpcInterceptor],
    );

    progressService = ProgressCalculatorClient(
      _createClientChannel('yajudge.ProgressCalculator'),
      interceptors: [_authGrpcInterceptor],
    );

    contentService = CourseContentProviderClient(
      _createClientChannel('yajudge.CourseContentProvider'),
      interceptors: [_authGrpcInterceptor],
    );

    coursesService = CourseManagementClient(
      _createClientChannel('yajudge.CourseManagement'),
      interceptors: [_authGrpcInterceptor],
    );

    deadlinesService = DeadlinesManagementClient(
      _createClientChannel('yajudge.DeadlinesManagement'),
      interceptors: [_authGrpcInterceptor],
    );

    submissionsService = SubmissionManagementClient(
      _createClientChannel('yajudge.SubmissionManagement'),
      interceptors: [_authGrpcInterceptor],
    );

    codeReviewService = CodeReviewManagementClient(
      _createClientChannel('yajudge.CodeReviewManagement'),
      interceptors: [_authGrpcInterceptor],
    );

    String sessionId = sessionCookie;
    _authGrpcInterceptor.sessionCookie = sessionId;

    log.fine('set initial sessionId = $sessionId');
  }

  dynamic _createClientChannel(String service) {
    try {
      return _createClientChannelUnsecure(service);
    }
    catch (e) {
      log.info('error creating client channel for service $service: $e');
      return null;
    }
  }

  dynamic _createClientChannelUnsecure(String service) {
    final scheme = _connectionUri.scheme;
    if (scheme != 'endpoints' && _clientChannels.isNotEmpty) {
      // reuse existing single point client channel
      final value = _clientChannels.values.first;
      _clientChannels[service] = value;
      log.fine('use existing client channel for service $service');
      return value;
    }
    if (scheme == 'http' || scheme == 'https') {
      // create single endpoint channel
      final host = _connectionUri.host;
      final secure = _connectionUri.scheme == 'https';
      int port = _connectionUri.port;
      if (port == 0) {
        port = secure ? 443 : 80;
      }
      final value = GrpcOrGrpcWebClientChannel.toSingleEndpoint(
        host: host,
        port: port,
        transportSecure: secure,
      );
      _clientChannels[service] = value;
      log.fine('created client channel $_connectionUri for service $service');
      return value;
    }
    if (scheme == 'endpoints') {
      // use separate client channels
      final endpoint = rpcProperties.endpoints[service]!;
      if (endpoint.isUnix) {
        final address = endpoint.toUnixInternetAddress();
        final value = ClientChannel(
          address,
          port: 0,
          options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
        );
        _clientChannels[service] = value;
        log.fine('created client channel ${endpoint.unixPath} for service $service');
        return value;
      }
      else {
        final value = GrpcOrGrpcWebClientChannel.toSingleEndpoint(
            host: endpoint.host, port: endpoint.port, transportSecure: endpoint.useSsl
        );
        _clientChannels[service] = value;
        log.fine('created client channel ${endpoint.host}:${endpoint.port} for service $service');
        return value;
      }
    }
    throw ArgumentError('unknown uri scheme');
  }

  Uri get connectionUri => _connectionUri;

  static void initialize(Uri connectionUri) {
    if (instance==null || instance!._connectionUri != connectionUri) {
      instance = ConnectionController(connectionUri);
      CourseContentController.initialize();
    }
  }

  Future<Session> getSession() async {
    if (_session.cookie.isNotEmpty && _session.user.id!=0) {
      return _session;
    }
    try {
      _session = await sessionsService.startSession(Session(cookie: sessionCookie));
      sessionCookie = _session.cookie;
      sessionUserEncrypted = _session.userEncryptedData;
      return _session;
    }
    catch (e) {
      return Session();
    }
  }

  void setSession(Session session) {
    _session = session;
    sessionUserEncrypted = session.userEncryptedData;
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
    return settingsValue ?? '';
  }

  set sessionCookie(String newValue) {
    PlatformsUtils.getInstance().saveSettingsValue('session', newValue);
    _authGrpcInterceptor.sessionCookie = newValue;
    log.fine('saved session key to application settings: $newValue');
  }

  set sessionUserEncrypted(String b64Data) {
    PlatformsUtils.getInstance().saveSettingsValue('session_user', b64Data);
    _authGrpcInterceptor.sessionUserEncrypted = b64Data;
  }

  String get sessionUserEncrypted {
    String? settingsValue = PlatformsUtils.getInstance().loadSettingsValue('session');
    return settingsValue ?? '';
    // return _authGrpcInterceptor.sessionUserEncrypted;
  }

}