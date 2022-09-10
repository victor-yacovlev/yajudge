import 'package:grpc/grpc.dart';
import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'dart:io' as io;

class ServicesConnector {
  final Logger log = Logger('ServicesConnector');
  final RpcProperties rpcProperties;
  late final ClientInterceptor interceptor;

  CourseContentProviderClient? _content;
  CourseManagementClient? _courses;
  DeadlinesManagementClient? _deadlines;
  ProgressCalculatorClient? _progress;
  CodeReviewManagementClient? _review;
  SessionManagementClient? _sessions;
  SubmissionManagementClient? _submissions;
  UserManagementClient? _users;

  ServicesConnector(this.rpcProperties) {
    interceptor = _PrivateServiceClientInterceptor(
      rpcProperties.privateToken,
      Logger.root,
    );
  }

  CourseContentProviderClient? get content {
    if (_content != null) {
      return _content;
    }
    try {
      final channel = _createExternalApiChannel('CourseContentProvider');
      _content =
          CourseContentProviderClient(channel, interceptors: [interceptor]);
      return _content;
    } catch (e) {
      log.severe('cant connect to content service: $e');
      return null;
    }
  }

  CourseManagementClient? get courses {
    if (_courses != null) {
      return _courses;
    }
    try {
      final channel = _createExternalApiChannel('CourseManagement');
      _courses = CourseManagementClient(channel, interceptors: [interceptor]);
      return _courses;
    } catch (e) {
      log.severe('cant connect to courses service: $e');
      return null;
    }
  }

  DeadlinesManagementClient? get deadlines {
    if (_deadlines != null) {
      return _deadlines;
    }
    try {
      final channel = _createExternalApiChannel('DeadlinesManagement');
      _deadlines =
          DeadlinesManagementClient(channel, interceptors: [interceptor]);
      return _deadlines;
    } catch (e) {
      log.severe('cant connect to deadlines service: $e');
      return null;
    }
  }

  ProgressCalculatorClient? get progress {
    if (_progress != null) {
      return _progress;
    }
    try {
      final channel = _createExternalApiChannel('ProgressCalculator');
      _progress =
          ProgressCalculatorClient(channel, interceptors: [interceptor]);
      return _progress;
    } catch (e) {
      log.severe('cant connect to progress service: $e');
      return null;
    }
  }

  CodeReviewManagementClient? get review {
    if (_review != null) {
      return _review;
    }
    try {
      final channel = _createExternalApiChannel('CodeReviewManagement');
      _review =
          CodeReviewManagementClient(channel, interceptors: [interceptor]);
      return _review;
    } catch (e) {
      log.severe('cant connect to review service: $e');
      return null;
    }
  }

  SessionManagementClient? get sessions {
    if (_sessions != null) {
      return _sessions;
    }
    try {
      final channel = _createExternalApiChannel('SessionManagement');
      _sessions = SessionManagementClient(channel, interceptors: [interceptor]);
      return _sessions;
    } catch (e) {
      log.severe('cant connect to sessions service: $e');
      return null;
    }
  }

  SubmissionManagementClient? get submissions {
    if (_submissions != null) {
      return _submissions;
    }
    try {
      final channel = _createExternalApiChannel('SubmissionManagement');
      _submissions =
          SubmissionManagementClient(channel, interceptors: [interceptor]);
      return _submissions;
    } catch (e) {
      log.severe('cant connect to submissions service: $e');
      return null;
    }
  }

  UserManagementClient? get users {
    if (_users != null) {
      return _users;
    }
    try {
      final channel = _createExternalApiChannel('UserManagement');
      _users = UserManagementClient(channel, interceptors: [interceptor]);
      return _users;
    } catch (e) {
      log.severe('cant connect to users service: $e');
      return null;
    }
  }

  ClientChannel _createExternalApiChannel(String apiName) {
    final endpoint = rpcProperties.endpoints['yajudge.$apiName'];
    if (endpoint == null) {
      throw ArgumentError(
          'service $apiName has not registered endpoint in configuration',
          apiName);
    }
    dynamic address;
    if (!endpoint.isUnix) {
      if (endpoint.host.isEmpty) {
        address = io.InternetAddress.anyIPv4;
      } else {
        address = endpoint.host;
      }
      return GrpcOrGrpcWebClientChannel.toSingleEndpoint(
          host: endpoint.host,
          port: endpoint.port,
          transportSecure: endpoint.useSsl);
    } else {
      address = io.InternetAddress(endpoint.unixPath,
          type: io.InternetAddressType.unix);
      return ClientChannel(
        address,
        port: 0,
        options:
            const ChannelOptions(credentials: ChannelCredentials.insecure()),
      );
    }
  }

  void invalidateConnections(String reason) {
    log.info('invalidating gRPC client connections due to $reason');
    _content = null;
    _courses = null;
    _deadlines = null;
    _progress = null;
    _review = null;
    _sessions = null;
    _submissions = null;
    _users = null;
  }
}

class _PrivateServiceClientInterceptor implements ClientInterceptor {
  final String privateApiToken;
  final Logger logger;

  _PrivateServiceClientInterceptor(this.privateApiToken, this.logger);

  @override
  ResponseStream<R> interceptStreaming<Q, R>(
      ClientMethod<Q, R> method,
      Stream<Q> requests,
      CallOptions options,
      ClientStreamingInvoker<Q, R> invoker) {
    CallOptions newOptions =
        options.mergedWith(CallOptions(metadata: _createMetadata()));
    return invoker(method, requests, newOptions);
  }

  @override
  ResponseFuture<R> interceptUnary<Q, R>(ClientMethod<Q, R> method, Q request,
      CallOptions options, ClientUnaryInvoker<Q, R> invoker) {
    CallOptions newOptions =
        options.mergedWith(CallOptions(metadata: _createMetadata()));
    return invoker(method, request, newOptions)
      ..onError((error, stackTrace) {
        logger.severe(
            'Error while executing external API call to ${method.path}: $error, stack trace: $stackTrace');
        return Future.error(error!);
      });
  }

  Map<String, String> _createMetadata() {
    final metadata = <String, String>{};
    metadata['token'] = privateApiToken;
    return metadata;
  }
}
