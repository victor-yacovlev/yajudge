import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'screens/screen_course_problem_onepage.dart';
import 'screens/screen_error.dart';
import 'controllers/connection_controller.dart';
import 'controllers/courses_controller.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:path/path.dart' as path;

import 'screens/screen_loading.dart';
import 'screens/screen_course.dart';
import 'screens/screen_course_reading.dart';
import 'screens/screen_dashboard.dart';
import 'screens/screen_login.dart';
import 'screens/screen_users.dart';
import 'screens/screen_users_edit.dart';
import 'screens/screen_users_import_csv.dart';


class App extends StatefulWidget {

  App() : super();

  @override
  State<StatefulWidget> createState() {
    return AppState();
  }
}

class AppState extends State<App> {
  String title = 'Yajudge';
  final log = Logger('AppState');

  AppState(): super();

  Widget buildLoginScreen(BuildContext context, {String returnPath = ''}) {
    return SizedBox.expand(
      child: Container(
          color: Theme.of(context).backgroundColor,
          child: Center(
              child: Container(
                  constraints: BoxConstraints(
                    maxHeight: 400,
                    maxWidth: 800,
                  ),
                  color: Theme.of(context).backgroundColor,
                  child: LoginScreen(appState: this),
              )
          )
      ),
    );
  }

  Widget generateWidgetForRoute(BuildContext context, RouteSettings settings) {
    String fullPath = path.normalize(settings.name!);
    String sessionId = ConnectionController.instance!.sessionCookie;

    log.info('generate widget for route $fullPath and session $sessionId');

    if (sessionId.isEmpty) {
      return buildLoginScreen(context);
    }

    final futureLoggedUser = ConnectionController.instance!.usersService
        .getProfile(Session(cookie: sessionId));

    return FutureBuilder(
      future: futureLoggedUser,
      builder: (BuildContext context, AsyncSnapshot<User> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return loadingWaitWidget(context);
        }
        final loggedUser = snapshot.requireData;
        return generateWidgetForPathAndLoggedUser(context, fullPath, loggedUser);
      },
    );
  }

  Widget generateWidgetForPathAndLoggedUser(BuildContext context, String fullPath, User loggedUser) {

    log.info('generate widget for path $fullPath and user ${loggedUser.id}');

    // check if user logged
    if (fullPath.startsWith('/login') || loggedUser.id == 0) {
      return buildLoginScreen(context, returnPath: fullPath);
    }

    // check for static paths than do not require additional data but logged user
    if (fullPath == '/users') {
      return UsersScreen(user: loggedUser);
    }
    if (fullPath == '/users/import_csv') {
      UsersImportCSVScreen(loggedInUser: loggedUser);
    }
    final RegExp usersMatch = RegExp(r'/users/(\d+|new|myself)');
    if (usersMatch.hasMatch(fullPath)) {
      final String arg = usersMatch.matchAsPrefix(fullPath)!.group(1)!;
      return UsersEditScreen(
          loggedInUser: loggedUser, userIdOrNewOrMyself: arg);
    }

    final coursesFilter = CoursesFilter(user: loggedUser);
    final futureCoursesList = ConnectionController.instance!.coursesService
        .getCourses(coursesFilter);

    return FutureBuilder(
      future: futureCoursesList,
      builder: (BuildContext context, AsyncSnapshot<CoursesList> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return loadingWaitWidget(context);
        }
        final coursesList = snapshot.requireData;
        return generateWidgetForPathAndLoggedUserAndCoursesList(
            context, fullPath, loggedUser, coursesList
        );
      },

    );
  }

  Widget generateWidgetForPathAndLoggedUserAndCoursesList(
      BuildContext context,
      String fullPath,
      User loggedUser,
      CoursesList coursesList,
      )
  {

    log.info('generate widget for path $fullPath, user ${loggedUser.id} and courses list of size ${coursesList.courses.length}');

    if (fullPath=='/') {
      return DashboardScreen(user: loggedUser, coursesList: coursesList);
    }

    if (fullPath.startsWith('/')) {
      fullPath = fullPath.substring(1);
    }
    if (fullPath.endsWith('/')) {
      fullPath = fullPath.substring(0, fullPath.length-1);
    }
    fullPath = path.normalize(fullPath);
    final pathParts = fullPath.split('/');

    // extract course prefix
    if (pathParts.isEmpty) {
      return ErrorScreen('Ошибка 404', fullPath);
    }

    final courseUrlPrefix = pathParts[0];
    CoursesList_CourseListEntry courseEntry = CoursesList_CourseListEntry();
    for (final entry in coursesList.courses) {
      if (entry.course.urlPrefix == courseUrlPrefix) {
        courseEntry = entry;
        break;
      }
    }
    if (courseEntry.course.urlPrefix.isEmpty) {
      return ErrorScreen('Ошибка 404', fullPath);
    }
    final courseTitle = courseEntry.course.name;
    return FutureBuilder(
      future: CoursesController.instance!.loadCourseData(courseEntry.course.dataId),
      builder: (BuildContext context, AsyncSnapshot<CourseData> courseDataFuture) {
        if (courseDataFuture.connectionState == ConnectionState.done) {
          CourseData data = courseDataFuture.requireData;
          return generateWidgetForCourse(context, loggedUser, courseEntry.course, data, pathParts);
        }
        else {
          return LoadingScreen(courseTitle, '');
        }
      },
    );
  }

  Widget generateWidgetForCourse(BuildContext context, User loggedUser, Course course, CourseData courseData, List<String> parts) {

    log.info('generate widget for  parts $parts, user ${loggedUser.id} and course prefix ${course.urlPrefix}');

    String sourcePath = parts.join('/'); // for error 404 message
    parts = parts.sublist(1);

    String sectionId = '';
    String lessonId = '';
    Section section = Section();
    Lesson lesson = Lesson();

    if (parts.isNotEmpty) {
      if (courseData.sections.length == 1 && courseData.sections.single.id.isEmpty) {
        lessonId = parts[0];
        parts = parts.sublist(1);
      }
      else {
        sectionId = parts[0];
        parts = parts.sublist(1);
        for (Section entry in courseData.sections) {
          if (entry.id == sectionId) {
            section = entry;
            break;
          }
        }
        if (section.id.isEmpty) {
          return ErrorScreen('Ошибка 404', sourcePath);
        }
        if (parts.isNotEmpty) {
          lessonId = parts[0];
          parts = parts.sublist(1);
          for (Lesson entry in section.lessons) {
            if (entry.id == lessonId) {
              lesson = entry;
              break;
            }
          }
          if (lesson.id.isEmpty) {
            return ErrorScreen('Ошибка 404', sourcePath);
          }
        }
      }
    }
    if (parts.isEmpty) {
      // no more parts in path - return course content with tree
      return CourseScreen(
        user: loggedUser,
        course: course,
        courseData: courseData,
        section: section,
        lesson: lesson,
      );
    }

    TextReading textReading = TextReading();
    ProblemData problemData = ProblemData();
    ProblemMetadata problemMetadata = ProblemMetadata();

    if (parts.first == 'problems') {
      // parse problem path and return problem screen
      parts = parts.sublist(1);
      if (parts.isEmpty) {
        // no problem id provided => error 404
        return ErrorScreen('Ошибка 404', sourcePath);
      }
      String problemId = parts[0];
      parts = parts.sublist(1);
      problemData = findProblemById(courseData, problemId);
      problemMetadata = findProblemMetadataByKey(courseData, problemId);
      if (problemData.id.isEmpty) {
        return ErrorScreen('Ошибка 404', sourcePath);
      }
      String problemScreenState = 'statement';
      if (parts.isNotEmpty) {
        problemScreenState = parts[0];
        parts = parts.sublist(1);
        if (!['statement', 'submit', 'history'].contains(problemScreenState)) {
          return ErrorScreen('Ошибка 404', sourcePath);
        }
      }
      return CourseProblemScreenOnePage(
        user: loggedUser,
        course: course,
        courseData: courseData,
        problemData: problemData,
        problemMetadata: problemMetadata,
      );
    }
    else if (parts.first == 'readings') {
      // parse text reading path and return reading screen
      parts = parts.sublist(1);
      if (parts.isEmpty) {
        // no reading id provided => error 404
        return ErrorScreen('Ошибка 404', sourcePath);
      }
      String readingId = parts[0];
      parts = parts.sublist(1);
      for (final entry in lesson.readings) {
        if (entry.id == readingId) {
          textReading = entry;
          break;
        }
      }
      if (textReading.id.isEmpty) {
        return ErrorScreen('Ошибка 404', sourcePath);
      }
      return CourseReadingScreen(user: loggedUser, textReading: textReading);
    }

    // nothing matched - error 404
    return ErrorScreen('Ошибка 404', sourcePath);
  }

  ThemeData buildThemeData() {
    return ThemeData(
        colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.blue)
            .copyWith(secondary: Colors.deepPurple)
    );
  }

  Widget loadingWaitWidget(BuildContext context) {
    return LoadingScreen('', 'Загрузка данных...');
  }

  @override
  Widget build(BuildContext context) {
    final onGenerateRoute = (RouteSettings settings) {
      return MaterialPageRoute(
          settings: settings,
          builder: (BuildContext context) {
            return generateWidgetForRoute(context, settings);
          }
      );
    };
    MaterialApp app =  MaterialApp(
      title: title,
      theme: buildThemeData(),
      // home: LoadingScreen('', 'Загрузка данных'),
      onGenerateRoute: onGenerateRoute,
      // initialRoute: appState.initialRoot,
    );
    return app;
  }
}

