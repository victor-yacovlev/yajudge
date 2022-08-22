import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';

import 'controllers/course_content_controller.dart';
import 'controllers/connection_controller.dart';
import 'client_app.dart';
import 'package:flutter/material.dart';

import 'utils/utils.dart';


void main(List<String>? arguments) async {
  List<String> args = arguments ?? [];

  bool verboseLogging = args.contains('--verbose') || args.contains('-v');
  Logger.root.level = verboseLogging ? Level.ALL : Level.INFO;
  Logger.root.onRecord.listen((LogRecord record) {
    print('${record.time} - ${record.loggerName}: ${record.level.name} - ${record.message}');
  });
  Logger.root.info('log level set to ${Logger.root.level.name}');


  Uri? apiUri;
  String? savedApiUri = PlatformsUtils.getInstance().loadSettingsValue('api_url');
  if (savedApiUri != null && savedApiUri.isNotEmpty) {
    apiUri = Uri.parse(savedApiUri);
  }
  else {
    if (kIsWeb) {
      apiUri = Uri(
        scheme: Uri.base.scheme,
        host: Uri.base.host,
        port: Uri.base.port,
      );
    }
  }

  if (apiUri != null) {
    ConnectionController.initialize(apiUri);
    Future<Session> futureSession = ConnectionController.instance!.getSession();
    futureSession.then((session) {
      final logMessage =
          'starting app with session id ${session.cookie} ' +
          'user id ${session.user.id} (login: ${session.user.login}) ' +
          'and initial route ${session.initialRoute}';
      Logger.root.info(logMessage);
      App app = App(initialSession: session);
      runApp(app);
    });
  }
  else {
    ConnectionController.initialize(Uri());
    Logger.root.info('no API URI set, so starting with empty session');
    App app = App(initialSession: Session());
    runApp(app);
  }
}

