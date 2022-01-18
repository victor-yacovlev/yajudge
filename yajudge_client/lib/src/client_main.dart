import 'package:grpc/grpc_connection_interface.dart';
import 'package:grpc/grpc_or_grpcweb.dart';
import 'client_app.dart';
import 'package:flutter/material.dart';
import 'utils/utils.dart';


void main([List<String>? arguments]) async {

  PlatformsUtils platformsSettings = PlatformsUtils.getInstance();
  platformsSettings.disableCoursesCache = true;

  Uri apiLocation = platformsSettings.getApiLocation();

  ClientChannelBase clientChannel = GrpcOrGrpcWebClientChannel.toSeparatePorts(
    host: apiLocation.host,
    grpcPort: apiLocation.port,
    grpcWebPort: apiLocation.port,
    grpcTransportSecure: false,
    grpcWebTransportSecure: apiLocation.scheme=='https',
  );

  App app = App(clientChannel: clientChannel);
  runApp(app);
}
