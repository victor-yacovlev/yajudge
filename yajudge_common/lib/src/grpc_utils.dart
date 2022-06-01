import 'package:grpc/grpc.dart';

extension SessionCapable on ServiceCall {
  String get session {
    final metadata = clientMetadata ?? {};
    final value = metadata.containsKey('session')? metadata['session']! : '';
    return value;
  }
}