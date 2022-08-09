import 'dart:io' as io;

import 'package:yaml/yaml.dart';
import 'config_file.dart';

class EndpointParseException extends Error {
  final String reason;
  final String source;
  EndpointParseException(this.reason, this.source);
  @override
  String toString() => 'while parsing $source: $reason';
}

class Endpoint {
  late final String service;
  late final String host;
  late final int port;
  late final String unixPath;
  late final bool useSsl;
  late final bool isUnix;

  Endpoint(this.service);

  @override
  String toString() => isUnix? unixPath : '$host:$port';

  bool connectionEquals(Endpoint other) {
    final typeMatch = isUnix==other.isUnix;
    final hostMatch = host==other.host;
    final sslMatch = useSsl==other.useSsl;
    final pathMatch = unixPath==other.unixPath;
    final portMatch = port==other.port;
    return typeMatch && hostMatch && sslMatch && pathMatch && portMatch;
  }

  factory Endpoint.fromUri(String service, String uriString) {
    final uri = Uri.parse(uriString);
    switch (uri.scheme) {
      case 'grpc':
      case 'http':
      case 'grpcs':
      case 'https':
        String hostName = uri.host;
        bool useSsl = ['grpcs', 'https'].contains(uri.scheme);
        int port = uri.port;
        if (port == 0 && (uri.scheme == 'grpc' || uri.scheme == 'grpcs')) {
          throw EndpointParseException('port is required for grpc(s):// scheme', uriString);
        }
        else if (port == 0 && uri.scheme == 'http') {
          port = 80;
        }
        else if (port == 0 && uri.scheme == 'https') {
          port = 443;
        }
        return Endpoint(service)
          ..host=hostName
          ..port=port
          ..unixPath=''
          ..useSsl=useSsl
          ..isUnix=false
        ;
      case 'grpc+unix':
      case 'grpcs+unix':
      case 'unix':
        bool useSsl = ['grpcs+unix'].contains(uri.scheme);
        String unixPath = uri.path;
        if (unixPath.isEmpty) {
          throw EndpointParseException('unix file name is empty', uriString);
        }
        return Endpoint(service)
          ..host=''
          ..port=0
          ..unixPath=unixPath
          ..useSsl=useSsl
          ..isUnix=true
        ;
      default:
        throw EndpointParseException('unknown endpoint uri scheme', uriString);
    }
  }

}

class RpcProperties {
  final String privateToken;
  final Map<String,Endpoint> endpoints = {};

  RpcProperties(this.privateToken);

  factory RpcProperties.fromYamlConfig(YamlMap conf, {
    String parentConfigFileName = '', String instanceName = '',
  }) {
    String privateToken = '';
    if (conf['private_token'] is String) {
      privateToken = conf['private_token'];
    }
    if (conf['private_token_file'] is String) {
      privateToken = readPrivateTokenFromFile(conf['private_token_file']);
    }
    dynamic endpointsValue = conf['endpoints'];
    RpcProperties result = RpcProperties(privateToken);
    YamlMap endpoints;
    if (endpointsValue is String) {
      final parentConfigFile = io.File(parentConfigFileName);
      final parentConfigDirectory = parentConfigFile.parent;
      final targetFileTemplate = '${parentConfigDirectory.path}/$endpointsValue';
      final targetFileName = expandPathEnvVariables(targetFileTemplate, instanceName);
      endpoints = parseYamlConfig(targetFileName);
    }
    else {
      endpoints = endpointsValue as YamlMap;
    }
    for (final entry in endpoints.entries) {
      String serviceName = entry.key as String;
      String uriString = entry.value as String;
      Endpoint endpoint = Endpoint.fromUri(serviceName, uriString);
      result.endpoints[serviceName] = endpoint;
    }
    return result;
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