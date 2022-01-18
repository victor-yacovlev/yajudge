import 'package:yaml/yaml.dart';

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
    return RpcProperties(
      publicToken: conf['public_token'],
      privateToken: conf['private_token'],
      host: conf['host'],
      port: conf['port'],
    );
  }

}