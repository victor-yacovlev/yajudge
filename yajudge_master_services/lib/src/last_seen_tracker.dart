import 'package:grpc/grpc.dart';

import 'service_call_extension.dart';

class LastSeenTracker {
  final Map<String,DateTime> trackingMap = {};

  DateTime lastSeenForSession(ServiceCall call) {
    final session = call.session;
    return trackingMap[session] ?? DateTime(2021);
  }

  void updateLastSeen(ServiceCall call) {
    final session = call.session;
    if (session.isEmpty) {
      return;
    }
    trackingMap[session] = DateTime.now();
  }

}