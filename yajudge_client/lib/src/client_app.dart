import 'dart:convert';

import 'package:grpc/grpc.dart';
import 'package:grpc/grpc_connection_interface.dart';
import 'screens/screen_course.dart';
import 'screens/screen_course_problem.dart';
import 'screens/screen_course_reading.dart';
import 'screens/screen_users_edit.dart';
import 'screens/screen_users.dart';
import 'screens/screen_users_import_csv.dart';
import 'widgets/unified_widgets.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'utils/utils.dart';
import 'screens/screen_dashboard.dart';
import 'screens/screen_login.dart';
import 'package:flutter/material.dart';

class App extends StatefulWidget {
  final ClientChannelBase clientChannel;
  App({required this.clientChannel}) : super();

  @override
  State<StatefulWidget> createState() {
    String? userJson = PlatformsUtils.getInstance().loadSettingsValue('User/object');
    String? sessionJson = PlatformsUtils.getInstance().loadSettingsValue('Session/object');
    Session? initialSession;
    User? initialUser;
    if (sessionJson!=null && sessionJson.isNotEmpty) {
      initialSession = Session.fromJson(sessionJson);
    }
    if (userJson!=null && userJson.isNotEmpty) {
      initialUser = User.fromJson(userJson);
    }
    return AppState(initialSession, initialUser, clientChannel);
  }
}

typedef void UserChangedCallback(User? user, CoursesList courseList);

class AuthGrpcInterceptor implements ClientInterceptor {

  String sessionCookie = '';

  @override
  ResponseStream<R> interceptStreaming<Q, R>(ClientMethod<Q, R> method, Stream<Q> requests, CallOptions options, ClientStreamingInvoker<Q, R> invoker) {
    return invoker(method, requests, options);
  }

  @override
  ResponseFuture<R> interceptUnary<Q, R>(ClientMethod<Q, R> method, Q request, CallOptions options, ClientUnaryInvoker<Q, R> invoker) {
    CallOptions newOptions = options.mergedWith(
      CallOptions(
        metadata: {
          'session': sessionCookie
        }
      )
    );
    return invoker(method, request, newOptions);
  }

}

class AppState extends State<App> {
  Session? _session;
  User? _userProfile;

  CoursesList _coursesList = CoursesList();
  static AppState? _instance;
  late final ClientChannelBase clientChannel;
  late final UserManagementClient usersService;
  late final CourseManagementClient coursesService;
  late final SubmissionManagementClient submissionsService;

  final AuthGrpcInterceptor authGrpcInterceptor = AuthGrpcInterceptor();

  List<UserChangedCallback> _userChangedCallbacks = List.empty(growable: true);

  AppState(Session? initialSession, User? initialUser, ClientChannelBase clientChannel) {
    _instance = this;
    this.clientChannel = clientChannel;
    usersService = UserManagementClient(clientChannel, interceptors: [authGrpcInterceptor]);
    coursesService = CourseManagementClient(clientChannel, interceptors: [authGrpcInterceptor]);
    submissionsService = SubmissionManagementClient(clientChannel, interceptors: [authGrpcInterceptor]);

    if (initialSession != null &&  initialUser !=null) {
      this.session = initialSession;
      this.userProfile = initialUser;
    }
  }


  void _loadCoursesListForUser(User user) {
    CoursesFilter filter = CoursesFilter()..user = user;
    coursesService.getCourses(filter)
    .then((CoursesList coursesList) {
      setState(() {
        _coursesList = coursesList;
      });
      String route = initialRoute;
      Navigator.pushReplacementNamed(context, route);
    })
    .onError((error, stackTrace) {
      Future.delayed(Duration(seconds: 2), () {
        // try again
        _loadCoursesListForUser(user);
      });
    });
  }

  void registerUserChangedCallback(UserChangedCallback cb) {
    _userChangedCallbacks.add(cb);
  }

  static AppState get instance {
    assert(_instance != null);
    return _instance!;
  }

  User? get userProfile => _userProfile;

  bool get loggedIn => userProfile!=null && session!=null;

  set userProfile(User? u) {
    _userProfile = u;
    String jsonValue = '';
    if (u == null) {
      _session = null;
      PlatformsUtils.getInstance().saveSettingsValue('Session/object', '');
    }
    if (u != null) {
      jsonValue = json.encode(u.writeToJsonMap());
      PlatformsUtils.getInstance().saveSettingsValue('User/object', jsonValue);
      _loadCoursesListForUser(u);
    }
  }

  Session? get session => _session;

  CoursesList get coursesList => _coursesList;

  set session(Session? s) {
    _session = s;
    authGrpcInterceptor.sessionCookie = s==null? '' : s.cookie;
    String jsonValue = '';
    if (s!=null) {
      jsonValue = json.encode(s.writeToJsonMap());
    }
    PlatformsUtils.getInstance().saveSettingsValue('Session/object', jsonValue);
    if (s==null) {
      _userProfile = null;
      PlatformsUtils.getInstance().saveSettingsValue('User/object', '');
    } else {
      usersService.getProfile(s).then((User u) => userProfile = u);
    }
  }

  String _title = 'Yajudge';

  void setTitle(String title) {
    _title = title;
  }

  String get initialRoute {
    if (_session==null) {
      return '/login';
    }
    Course? defaultCourse;
    String result = '/';
    // if (_userProfile!.defaultRole == UserRole_Student) {
    //   // check if there is only one course available to skip welcome screen
    //   CoursesService.instance.getCourses(CoursesFilter()..user=_userProfile!)
    //       .then((CoursesList coursesList) {
    //         if (coursesList.courses.length == 1) {
    //           defaultCourse = coursesList.courses.first.course;
    //         }
    //   });
    // }
    if (defaultCourse != null) {
      result += defaultCourse.urlPrefix + '/';
      String? subroute = PlatformsUtils.getInstance()
          .loadSettingsValue('Subroute/' + defaultCourse.urlPrefix);
      if (subroute != null) {
        result += subroute;
      }
    }
    return result;
  }


  Map<String, WidgetBuilder> createRoutes() {
    return {
      '/login': (_) => SizedBox.expand(
        child: Container(
            color: Theme.of(context).backgroundColor,
            child: Center(
                child: Container(
                    constraints: BoxConstraints(
                      maxHeight: 400,
                      maxWidth: 800,
                    ),
                    color: Theme.of(context).backgroundColor,
                    child: LoginScreen()
                )
            )
        ),
      ),
      '/': (_) => DashboardScreen(),
      '/users': (_) => UsersScreen(),
      '/users/import_csv': (_) => UsersImportCSVScreen(),
    };
  }

  Widget generateWidgetForRoute(BuildContext context, RouteSettings settings) {
    // when no static routes matched
    final RegExp usersMatch = RegExp(r'/users/(\d+|new|myself)');
    final String path = settings.name!;
    if (usersMatch.hasMatch(path)) {
      final String arg = usersMatch.matchAsPrefix(path)!.group(1)!;
      return UsersEditScreen(arg);
    }

    // text readings of problem on course
    // Regexp to match:
    // - group 1: course url prefix
    // - group 2: section id
    // - group 3: lesson id
    // - group 4: 'readings' or 'problems' to choose proper page type
    // - group 5: part name
    // - group 6: /tab
    // - group 7: tab
    final RegExp rxCoursesLessonParts = RegExp(
        r'/([0-9a-z_-]+)/([0-9a-z_-]+)/([0-9a-z_-]+)/(readings|problems)/([0-9a-z_-]+)(/(statement|submissions|discussion))?');
    final RegExpMatch? lessonPartMatch = rxCoursesLessonParts.firstMatch(path);
    if (lessonPartMatch != null) {
      final String pathUrlPrefix = lessonPartMatch[1]!;
      final String sectionId = lessonPartMatch[2]!;
      final String lessonId = lessonPartMatch[3]!;
      final String kind = lessonPartMatch[4]!;
      final String name = lessonPartMatch[5]!;
      final String key = '/' + sectionId + '/' + lessonId + '/' + name;

      for (CoursesList_CourseListEntry courseEntry in _coursesList.courses) {
        final String courseDataId = courseEntry.course.dataId;
        final String courseUrlPrefix = courseEntry.course.urlPrefix;
        if (courseUrlPrefix == pathUrlPrefix) {
          if (kind == 'readings') {
            return CourseReadingScreen(courseDataId, key, null);
          } else if (kind == 'problems') {
            String tab = 'statement';
            if (lessonPartMatch[7] != null) {
              tab = lessonPartMatch[7]!;
            }
            return CourseProblemScreen(courseEntry.course.id.toInt(), courseDataId, key, null, null, tab);
          }
        }
      }
    }

    // courses have short links names by them ID's
    // Regexp to match:
    // - group 1: course url prefix
    // - group 3: section id
    // - group 5: level id
    final RegExp rxCourses =
        RegExp(r'/([0-9a-z_-]+)(/([0-9a-z_-]*)(/([0-9a-z_-]+))?)?');
    final RegExpMatch? coursesMatch = rxCourses.firstMatch(path);
    if (coursesMatch != null) {
      final int groupCount = coursesMatch.groupCount;
      final String pathUrlPrefix = coursesMatch.group(1)!;
      final String? sectionId = groupCount >= 3 ? coursesMatch[3] : null;
      final String? lessonId = groupCount >= 5 ? coursesMatch[5] : null;
      for (CoursesList_CourseListEntry courseEntry in _coursesList.courses) {
        final String courseDataId = courseEntry.course.dataId;
        final String courseUrlPrefix = courseEntry.course.urlPrefix;
        if (courseUrlPrefix == pathUrlPrefix) {
          return CourseScreen(
            courseEntry.course.name,
            courseDataId,
            courseUrlPrefix,
            sectionKey: sectionId,
            lessonKey: lessonId,
          );
        }
      }
    }
    return Center(
        child: Container(
            margin: EdgeInsets.all(50),
            padding: EdgeInsets.all(20),
            constraints: BoxConstraints(
              minWidth: 400,
              maxHeight: 400,
            ),
            decoration: BoxDecoration(
              border:
                  Border.all(color: Theme.of(context).errorColor, width: 2.0),
            ),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Ошибка 404', style: Theme.of(context).textTheme.headline5),
              Padding(
                  child:
                      Text(path, style: Theme.of(context).textTheme.bodyText1),
                  padding: EdgeInsets.all(20)),
              YTextButton('Назад', () {
                Navigator.pop(context);
              }, color: Theme.of(context).errorColor)
            ])));
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    // String initialRoute;
    // if (_sessionId.isNotEmpty) {
    //   initialRoute = '/';
    // } else {
    //   initialRoute = '/login';
    // }
    return MaterialApp(
      title: _title,
      theme: ThemeData(
          colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.blue).copyWith(secondary: Colors.deepPurple)),
      initialRoute: initialRoute,
      routes: createRoutes(),
      onGenerateRoute: (RouteSettings settings) {
        return MaterialPageRoute(
            settings: settings,
            builder: (BuildContext context) {
              return generateWidgetForRoute(context, settings);
            });
      },
    );
  }

  Future<CourseData> loadCourseData(String courseId) async {
    CourseContentResponse? cached = null;
        // await PlatformsUtils.getInstance().findCachedCourse(courseId);

    // TODO remove from production code
    // cache is null while in development
    cached = null;

    CourseContentRequest request = CourseContentRequest()
      ..courseDataId = courseId;
    if (cached != null) {
      request.cachedTimestamp = cached.lastModified;
    }
    late CourseContentResponse response;
    try {
      response = await coursesService.getCoursePublicContent(request);
    } catch (error) {
      return Future.error(error);
    }
    if (response.status == CourseContentStatus.NOT_CHANGED) {
      assert(cached != null);
      return Future.value(cached!.data);
    } else {
      // PlatformsUtils.getInstance().storeCourseInCache(response);
      return Future.value(response.data);
    }
  }
}

