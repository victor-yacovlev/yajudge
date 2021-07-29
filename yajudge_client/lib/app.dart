import 'package:yajudge_client/screens/screen_course.dart';
import 'package:yajudge_client/screens/screen_course_problem.dart';
import 'package:yajudge_client/screens/screen_course_reading.dart';
import 'package:yajudge_client/screens/screen_users_edit.dart';
import 'package:yajudge_client/screens/screen_users.dart';
import 'package:yajudge_client/screens/screen_users_import_csv.dart';
import 'package:yajudge_client/widgets/unified_widgets.dart';
import 'package:yajudge_client/wsapi/courses.dart';
import 'utils/utils.dart';
import 'screens/screen_dashboard.dart';
import 'screens/screen_login.dart';
import 'widgets/root_wrapper.dart';
import 'wsapi/connection.dart';
import 'wsapi/users.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class App extends StatefulWidget {
  String _sessionId;

  App(String sessionId)
      : _sessionId = sessionId,
        super();

  @override
  State<StatefulWidget> createState() {
    return AppState(_sessionId);
  }
}

typedef void UserChangedCallback(User? user, CoursesList courseList);

class AppState extends State<App> {
  String _sessionId = '';
  User? _userProfile;
  CoursesList _coursesList = CoursesList();
  static AppState? _instance;

  List<UserChangedCallback> _userChangedCallbacks = List.empty(growable: true);

  AppState(String sessionId) {
    _instance = this;
    if (sessionId.isNotEmpty) this.sessionId = sessionId;
  }

  void registerUserChangedCallback(UserChangedCallback cb) {
    _userChangedCallbacks.add(cb);
  }

  static AppState get instance {
    assert(_instance != null);
    return _instance!;
  }

  User? get userProfile => _userProfile;

  String get sessionId => _sessionId;

  CoursesList get coursesList => _coursesList;

  set sessionId(String sessionId) {
    _sessionId = sessionId;
    RpcConnection.getInstance().setSessionCookie(sessionId);
    Session session = Session();
    session.cookie = sessionId;
    PlatformsUtils.getInstance()
        .saveSettingsValue('User/session_id', sessionId);
    if (sessionId == '') {
      _userProfile = null;
      return;
    }
    UsersService.instance.getProfile(session).then((User user) {
      setState(() {
        _userProfile = user;
      });
      CoursesFilter filter = CoursesFilter()..user = user;
      CoursesService.instance
          .getCourses(filter)
          .then((CoursesList coursesList) {
        setState(() {
          _coursesList = coursesList;
        });
        for (UserChangedCallback cb in _userChangedCallbacks) {
          cb(user, coursesList);
        }
      });
    }).onError((error, stackTrace) {
      Future.delayed(Duration(seconds: 2), () {
        // try again
        this.sessionId = sessionId;
      });
    });
  }

  String _title = 'Yajudge';

  void setTitle(String title) {
    _title = title;
  }

  String userProfileName() {
    if (_userProfile != null) {
      User user = _userProfile!;
      String visibleName;
      if (user.firstName != null &&
          user.firstName!.isNotEmpty &&
          user.lastName != null &&
          user.lastName!.isNotEmpty) {
        visibleName = user.firstName! + ' ' + user.lastName!;
      } else {
        visibleName = 'ID (' + user.id.toString() + ')';
      }
      return visibleName;
    } else {
      return '';
    }
  }

  Map<String, WidgetBuilder> createRoutes() {
    return {
      '/login': (_) => RootWrapper(child: LoginScreen(), title: 'Вход'),
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

      for (final CourseListEntry courseEntry in _coursesList.courses) {
        final CourseData courseData = courseEntry.course.courseData!;
        final String courseUrlPrefix = courseEntry.course.urlPrefix;
        if (courseUrlPrefix == pathUrlPrefix) {
          if (kind == 'readings') {
            return CourseReadingScreen(courseData.id, key, null);
          } else if (kind == 'problems') {
            String tab = 'statement';
            if (lessonPartMatch[7] != null) {
              tab = lessonPartMatch[7]!;
            }
            return CourseProblemScreen(courseEntry.course.id, courseData.id, key, null, null, tab);
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
      for (final CourseListEntry courseEntry in _coursesList.courses) {
        final String courseDataId = courseEntry.course.courseData!.id;
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
    String initialRoute;
    if (_sessionId.isNotEmpty) {
      initialRoute = '/';
    } else {
      initialRoute = '/login';
    }

    return MaterialApp(
      title: _title,
      theme: ThemeData(
          primarySwatch: Colors.blue, accentColor: Colors.deepPurple),
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
    CourseContentResponse? cached =
        await PlatformsUtils.getInstance().findCachedCourse(courseId);
    CourseContentRequest request = CourseContentRequest()
      ..courseDataId = courseId;
    if (cached != null) {
      request.cachedTimestamp = cached.lastModified;
    }
    late CourseContentResponse response;
    try {
      response = await CoursesService.instance.getCoursePublicContent(request);
    } catch (error) {
      return Future.error(error);
    }
    if (response.status == CourseContentStatus_NOT_CHANGED) {
      assert(cached != null);
      return Future.value(cached!.data);
    } else {
      PlatformsUtils.getInstance().storeCourseInCache(response);
      return Future.value(response.data);
    }
  }
}

class CupertinoNotAnimatedPageRoute extends CupertinoPageRoute {
  WidgetBuilder builder;
  CupertinoNotAnimatedPageRoute(this.builder) : super(builder: builder);

}