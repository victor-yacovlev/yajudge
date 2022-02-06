import 'package:logging/logging.dart';

import 'controllers/courses_controller.dart';
import 'controllers/connection_controller.dart';
import 'client_app.dart';
import 'package:flutter/material.dart';


void main(List<String>? arguments) {
  List<String> args = arguments!=null? arguments : [];

  bool verboseLogging = args.contains('--verbose') || args.contains('-v');
  Logger.root.level = verboseLogging ? Level.ALL : Level.INFO;
  Logger.root.onRecord.listen((LogRecord record) {
    print('${record.time} - ${record.loggerName}: ${record.level.name} - ${record.message}');
  });
  Logger.root.info('log level set to ${Logger.root.level.name}');
  ConnectionController.initialize(args);
  CoursesController.initialize();

  App app = App();
  runApp(app);

}
