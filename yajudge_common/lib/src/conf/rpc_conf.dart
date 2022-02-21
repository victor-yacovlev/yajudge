import 'package:yaml/yaml.dart';

import 'config_file.dart';

class RpcProperties {
  late final String publicToken;
  late final String privateToken;
  late final String host;
  late final int port;

  RpcProperties({
    required this.publicToken,
    required this.privateToken,
    required this.host,
    required this.port
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
    return RpcProperties(
      publicToken: publicToken,
      privateToken: privateToken,
      host: conf['host'],
      port: conf['port'],
    );
  }

}