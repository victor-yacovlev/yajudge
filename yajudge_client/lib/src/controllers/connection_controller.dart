import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';
import 'package:grpc/grpc_connection_interface.dart';
import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import '../utils/utils.dart';

class AuthGrpcInterceptor implements ClientInterceptor {
  String sessionCookie = '';

  @override
  ResponseStream<R> interceptStreaming<Q, R>(
      ClientMethod<Q, R> method,
      Stream<Q> requests,
      CallOptions options,
      ClientStreamingInvoker<Q, R> invoker) {
    return invoker(method, requests, options);
  }

  @override
  ResponseFuture<R> interceptUnary<Q, R>(ClientMethod<Q, R> method, Q request,
      CallOptions options, ClientUnaryInvoker<Q, R> invoker) {
    CallOptions newOptions =
    options.mergedWith(CallOptions(metadata: {'session': sessionCookie}));
    return invoker(method, request, newOptions);
  }
}

class ConnectionController {

  static ConnectionController? instance;
  final log = Logger('ConnectionController');

  late final ClientChannelBase _clientChannel;
  final _authGrpcInterceptor = AuthGrpcInterceptor();
  late final UserManagementClient usersService;
  late final CourseManagementClient coursesService;
  late final SubmissionManagementClient submissionsService;

  ConnectionController(List<String> arguments) {

    PlatformsUtils platformsSettings = PlatformsUtils.getInstance();
    Uri grpcApiLocation = platformsSettings.getGrpcApiUri(arguments);
    Uri webApiLocation = platformsSettings.getWebApiUri(arguments);

    String host = grpcApiLocation.host.isEmpty? webApiLocation.host : grpcApiLocation.host;

    _clientChannel = GrpcOrGrpcWebClientChannel.toSeparatePorts(
      host: host,
      grpcPort: grpcApiLocation.port,
      grpcWebPort: webApiLocation.port,
      grpcTransportSecure: false,
      grpcWebTransportSecure: webApiLocation.scheme=='https',
    );

    if (kIsWeb && (webApiLocation.port >= 9000)) {
      Logger.root.level = Level.ALL;
      Logger.root.info('log level changed to ${Logger.root.level.name} due to running port number > 9000');
    }
    log.fine('created client channel to host $host');

    usersService = UserManagementClient(
        _clientChannel,
        interceptors: [_authGrpcInterceptor]);

    coursesService = CourseManagementClient(
        _clientChannel,
        interceptors: [_authGrpcInterceptor]);

    submissionsService = SubmissionManagementClient(
        _clientChannel,
        interceptors: [_authGrpcInterceptor]);

    String sessionId = sessionCookie;
    _authGrpcInterceptor.sessionCookie = sessionId;

    log.fine('set initial sessionId = $sessionId');
  }

  static void initialize(List<String> arguments) {
    assert(instance == null);
    instance = ConnectionController(arguments);
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