import 'dart:math';

import 'package:yaml/yaml.dart';

import 'config_file.dart';

class RpcProperties {
  late final String publicToken;
  late final String privateToken;
  late final String host;
  late final int port;
  late final bool useSsl;

  RpcProperties({
    required this.publicToken,
    required this.privateToken,
    required this.host,
    required this.port,
    required this.useSsl,
  });

  factory RpcProperties.fromYamlConfig(YamlMap conf) {
    String publicToken = '';
    if (conf['public_token'] is String) {
      publicToken = conf['public_token'];
    }
    String privateToken = '';
    if (conf['private_token'] is String) {
      privateToken = conf['private_token'];
    }
    if (conf['private_token_file'] is String) {
      privateToken = readPrivateTokenFromFile(conf['private_token_file']);
    }
    bool useSsl = false;
    if (conf['use_ssl'] is bool) {
      useSsl = conf['use_ssl'];
    }
    return RpcProperties(
      publicToken: publicToken,
      privateToken: privateToken,
      host: conf['host'],
      port: conf['port'],
      useSsl: useSsl,
    );
  }
}

class WebRpcProperties {
  late final String host;
  late final int port;
  late final String engine;
  late final String logFilePath;

  WebRpcProperties({
    this.host = 'any',
    this.port = 8095,
    this.engine = '',
    this.logFilePath = '',
  });

  factory WebRpcProperties.fromYamlConfig(YamlMap conf) {
    String engine = '';
    if (conf['engine'] is String && conf['engine']!='disabled' && conf['engine']!='none') {
      engine = conf['engine'];
    }
    String host = 'any';
    if (conf['host'] is String) {
      host = conf['host'];
    }
    int port = 8095;
    if (conf['port'] is int) {
      port = conf['port'];
    }
    String logFilePath = '';
    if (conf['log_file'] is String) {
      logFilePath = conf['log_file'];
    }
    return WebRpcProperties(
      host: host,
      engine: engine,
      port: port,
      logFilePath: logFilePath,
    );
  }

}