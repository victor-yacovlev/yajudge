import 'wsapi/connection.dart';
import 'wsapi/users.dart';
import 'wsapi/courses.dart';

import 'app.dart';
import 'package:flutter/material.dart';
import 'utils/utils.dart';


void main(List<String> arguments) {
  String? wsApiUrl;
  String? theme;
  bool disableCoursesCache = false;

  for (String arg in arguments) {
    arg = arg.toLowerCase();
    if (arg.startsWith('--wsapiurl=')) {
      wsApiUrl = arg.substring(11);
    } else if (arg.startsWith('--theme=')) {
      theme = arg.substring(8);
    } else if (arg == '--disable-courses-cache') {
      disableCoursesCache = true;
    }
  }

  PlatformsUtils platformsSettings = PlatformsUtils.getInstance();
  platformsSettings.disableCoursesCache = disableCoursesCache;
  if (theme != null) {
    platformsSettings.overrideTheme = theme;
  }

  if (wsApiUrl == null) {
    wsApiUrl = platformsSettings.getWsApiUrl();
  }
  if (wsApiUrl == null) {
    wsApiUrl = 'ws://localhost:8080/api-ws';
  }

  String? currentSessionCookie = platformsSettings.loadSettingsValue('User/session_id');
  if (currentSessionCookie == null) {
    currentSessionCookie = '';
  }

  RpcConnection rpcConn = new RpcConnection(wsApiUrl);
  UsersService usersService = new UsersService(rpcConn);
  CoursesService coursesService = new CoursesService(rpcConn);


  App app = App(currentSessionCookie);
  runApp(app);
}
