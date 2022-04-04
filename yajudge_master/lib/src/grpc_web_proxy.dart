import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:path/path.dart' as path;
import 'dart:io' as io;

abstract class AbstractGrpcWebProxyService {
  final RpcProperties rpcProperties;
  final WebRpcProperties webRpcProperties;
  final Logger logger;

  AbstractGrpcWebProxyService(this.rpcProperties, this.webRpcProperties)
      : logger = Logger('GrpcWebProxy');

  void start();
  void stop();

  factory AbstractGrpcWebProxyService.create({
    required WebRpcProperties webRpcProperties,
    required RpcProperties rpcProperties,
  }) {
    String engine = webRpcProperties.engine;
    bool bundled = false;
    const bundledPrefix = 'bundled-';
    if (engine.startsWith(bundledPrefix)) {
      engine = engine.substring(bundledPrefix.length);
      bundled = true;
    }

    // check for engine existence
    String engineExecutable = '';
    if (bundled) {
      final serverBinaryExecutable = io.Platform.script.path;
      final serverBinaryDirName = path.dirname(serverBinaryExecutable);
      engineExecutable = '$serverBinaryDirName/$engine';
      if (!io.File(engineExecutable).existsSync()) {
        throw Exception('bundled grpc web proxy not found: $engineExecutable');
      }
    }
    else {
      if (path.isAbsolute(engine)) {
        if (!io.File(engine).existsSync()) {
          throw Exception('grpc web proxy executable not found: $engine');
        }
      }
      else {
        final pathEntries = io.Platform.environment['PATH']!.split(':');
        bool found = false;
        for (final pathDir in pathEntries) {
          engineExecutable = '$pathDir/$engine';
          if (io.File(engineExecutable).existsSync()) {
            found = true;
            break;
          }
        }
        if (!found) {
          throw Exception('grpc web proxy executable not found: $engine');
        }
      }
    }

    // check for known engines
    String engineName;
    if (path.isAbsolute(engine)) {
      engineName = path.basenameWithoutExtension(engine);
    }
    else {
      engineName = engine;
    }
    if (engineName == 'envoy') {
      // envoy proxy from https://www.envoyproxy.io
      throw UnimplementedError('engine envoy not implemented yet');
    }
    else if (engineName == 'grpcwebproxy') {
      // proxy from from project https://github.com/improbable-eng/grpc-web
      return GrpcWebProxyWrapper(rpcProperties, webRpcProperties, engineExecutable);
    }
    else {
      throw Exception('unknown grpc-web proxy engine');
    }
  }
}

abstract class AbstractGrpcWebProxyWrapper extends AbstractGrpcWebProxyService {
  final String _executablePath;
  io.Process? _process;

  @override
  void stop() {
    if (_process == null) {
      return;
    }
    _process!.kill(io.ProcessSignal.sigkill);
  }

  AbstractGrpcWebProxyWrapper(RpcProperties rpcProperties, WebRpcProperties webRpcProperties, this._executablePath)
      : super(rpcProperties, webRpcProperties);
}

class GrpcWebProxyWrapper extends AbstractGrpcWebProxyWrapper {

  GrpcWebProxyWrapper(RpcProperties rpcProperties, WebRpcProperties webRpcProperties, String executablePath)
      : super(rpcProperties, webRpcProperties, executablePath);

  @override
  void start() async {
    final arguments = _prepareArguments();
    try {
      _process = await io.Process.start(_executablePath, arguments, runInShell: true);
      logger.info('started grpcwebproxy[$_executablePath], PID = ${_process!.pid}');
    }
    catch (e) {
      logger.shout('cant start grpcwebproxy[$_executablePath]: $e');
      rethrow;
    }
    final logFile = io.File(webRpcProperties.logFilePath);
    logFile.writeAsStringSync('started $_executablePath $arguments', flush: true);
    _process!.stdout.pipe(logFile.openWrite(mode: io.FileMode.writeOnlyAppend));
  }

  List<String> _prepareArguments() {
    String backendHost = rpcProperties.host=='any' ? 'localhost' : rpcProperties.host;
    String bindAddress = webRpcProperties.host=='any' ? '0.0.0.0' : webRpcProperties.host;
    return [
      '--backend_addr=$backendHost:${rpcProperties.port}',
      '--backend_tls_noverify',
      '--allow_all_origins',
      '--run_tls_server=false',
      '--server_bind_address=$bindAddress',
      '--server_http_debug_port=${webRpcProperties.port}',
    ];
  }

}
