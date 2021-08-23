import 'package:yajudge_client/wsapi/submissions.dart';

import 'wsapi/connection.dart';
import 'wsapi/users.dart';
import 'wsapi/courses.dart';

import 'app.dart';
import 'package:flutter/material.dart';
import 'utils/utils.dart';


void main([List<String>? arguments]) {
  String? wsApiUrl;
  bool disableCoursesCache = false;

  if (arguments != null) {
    for (String arg in arguments) {
      arg = arg.toLowerCase();
      if (arg.startsWith('--wsapiurl=')) {
        wsApiUrl = arg.substring(11);
      } else if (arg == '--disable-courses-cache') {
        disableCoursesCache = true;
      }
    }
  }

  PlatformsUtils platformsSettings = PlatformsUtils.getInstance();
  platformsSettings.disableCoursesCache = disableCoursesCache;

  if (wsApiUrl == null) {
    wsApiUrl = platformsSettings.getWsApiUrl();
  }
  if (wsApiUrl == null) {
    wsApiUrl = 'ws://localhost:8080/api-ws';
  }

  RpcConnection rpcConn = new RpcConnection(wsApiUrl);
  UsersService usersService = new UsersService(rpcConn);
  CoursesService coursesService = new CoursesService(rpcConn);
  SubmissionService submissionService = new SubmissionService(rpcConn);


  App app = App();
  runApp(app);
}
