import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';

import 'controllers/courses_controller.dart';
import 'controllers/connection_controller.dart';
import 'client_app.dart';
import 'package:flutter/material.dart';


void main(List<String>? arguments) async {
  List<String> args = arguments!=null? arguments : [];

  bool verboseLogging = args.contains('--verbose') || args.contains('-v');
  Logger.root.level = verboseLogging ? Level.ALL : Level.INFO;
  Logger.root.onRecord.listen((LogRecord record) {
    print('${record.time} - ${record.loggerName}: ${record.level.name} - ${record.message}');
  });
  Logger.root.info('log level set to ${Logger.root.level.name}');
  ConnectionController.initialize(args);
  CoursesController.initialize();

  String initialRoute = await getInitialRoute();

  App app = App(initialRoute: initialRoute);
  runApp(app);
}

Future<String> getInitialRoute() async {
  final usersService = ConnectionController.instance!.usersService;
  final sessionId = ConnectionController.instance!.sessionCookie;
  try {
    final session = await usersService.startSession(Session(cookie: sessionId));
    return session.redirectUrl;
  }
  catch (e) {
    return "/login";
  }
}
