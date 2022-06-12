// ignore_for_file: unused_local_variable

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'screens/screen_course_progress.dart';
import 'screens/screen_enrollments.dart';
import 'screens/screen_enrollments_group.dart';
import 'screens/screen_submission.dart';
import 'screens/screen_course_problem.dart';
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
import 'screens/screen_submissions_list.dart';
import 'screens/screen_users.dart';
import 'screens/screen_users_edit.dart';
import 'screens/screen_users_import_csv.dart';


class App extends StatefulWidget {

  final Session initialSession;

  App({required this.initialSession}) : super();

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
    log.info('generate widget for route $fullPath');
    final futureSession = ConnectionController.instance!.getSession();
    return FutureBuilder(
      future: futureSession,
      builder: (BuildContext context, AsyncSnapshot<Session> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return loadingWaitWidget(context);
        }
        Session session = snapshot.requireData;
        if (session.cookie.isEmpty || session.user.id==0) {
          return buildLoginScreen(context, returnPath: fullPath);
        }
        else {
          return generateWidgetForPathAndLoggedUser(context, fullPath, session.user);
        }
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

    final RegExp submissionsWithNumber = RegExp(r'/submissions/([0-9a-z_-]+)/(\d+)');
    if (submissionsWithNumber.hasMatch(fullPath)) {
      final match = submissionsWithNumber.matchAsPrefix(fullPath)!;
      final courseUrlPrefix = match.group(1)!;
      final submissionId = int.parse(match.group(2)!);
      return SubmissionScreen(
        user: loggedUser,
        courseUrlPrefix: courseUrlPrefix,
        submissionId: Int64(submissionId),
      );
    }

    final RegExp submissionsWithFilters = RegExp(r'/submissions/([0-9a-z_-]+)(/filter:.+)?');
    if (submissionsWithFilters.hasMatch(fullPath)) {
      final match = submissionsWithFilters.matchAsPrefix(fullPath)!;
      final courseUrlPrefix = match.group(1)!;
      final filterString = match.groupCount > 2 ? match.group(2) : '';
      // TODO parse filter string
      return SubmissionsListScreen(
        loggedUser: loggedUser,
        courseUrlPrefix: courseUrlPrefix,
      );
    }

    final RegExp progressWithFilters = RegExp(r'/progress/([0-9a-z_-]+)(/filter:.+)?');
    if (progressWithFilters.hasMatch(fullPath)) {
      final match = progressWithFilters.matchAsPrefix(fullPath)!;
      final courseUrlPrefix = match.group(1)!;
      final filterString = match.groupCount > 2 ? match.group(2) : '';
      // TODO parse filter string
      return CourseProgressScreen(
        loggedUser: loggedUser,
        courseUrlPrefix: courseUrlPrefix,
      );
    }

    final RegExp enrollmentsWithGroup = RegExp(r'/enrollments/([0-9a-z_-]+)/(.+)');
    if (enrollmentsWithGroup.hasMatch(fullPath)) {
      final match = enrollmentsWithGroup.matchAsPrefix(fullPath)!;
      final courseUrlPrefix = match.group(1)!;
      final groupName = match.group(2)!;
      return EnrollmentsGroupScreen(
        loggedUser: loggedUser,
        courseUrlPrefix: courseUrlPrefix,
        groupName: groupName,
      );
    }

    final RegExp enrollments = RegExp(r'/enrollments/([0-9a-z_-]+)');
    if (enrollments.hasMatch(fullPath)) {
      final match = enrollments.matchAsPrefix(fullPath)!;
      final courseUrlPrefix = match.group(1)!;
      return EnrollmentsScreen(
        loggedUser: loggedUser,
        courseUrlPrefix: courseUrlPrefix,
      );
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
    List<String> pathParts = fullPath.split('/');

    // extract course prefix
    if (pathParts.isEmpty) {
      return ErrorScreen('Ошибка 404', '');
    }

    final courseUrlPrefix = pathParts[0];
    pathParts = pathParts.sublist(1);
    CoursesList_CourseListEntry courseEntry = CoursesList_CourseListEntry();
    for (final entry in coursesList.courses) {
      if (entry.course.urlPrefix == courseUrlPrefix) {
        courseEntry = entry;
        break;
      }
    }
    if (courseEntry.course.urlPrefix.isEmpty) {
      return ErrorScreen('Ошибка 404', '');
    }
    final courseTitle = courseEntry.course.name;
    String pathTail = pathParts.join('/');
    final futureData = CoursesController.instance!.loadCourseData(courseEntry.course.dataId);

    return FutureBuilder(
      future: futureData,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          final content = snapshot.requireData as CourseData;
          return generateWidgetForCourse(
              context,
              loggedUser,
              courseEntry,
              content,
              pathTail,
          );
        }
        else {
          return LoadingScreen(courseTitle, '');
        }
      },
    );
  }

  Widget generateWidgetForCourse(BuildContext context, User loggedUser, CoursesList_CourseListEntry courseEntry, CourseData courseData, String sourcePath) {

    log.info('generate widget for $sourcePath, user ${loggedUser.id} and course prefix ${courseEntry.course.urlPrefix}');

    List<String> parts = sourcePath.split('/');

    String sectionId = '';
    String lessonId = '';
    Section section = Section();
    Lesson lesson = Lesson();

    if (parts.isNotEmpty) {
      if (courseData.sections.length == 1 && courseData.sections.single.id.isEmpty) {
        lessonId = parts[0];
        parts = parts.sublist(1);
        section = courseData.sections.single;
        for (Lesson entry in section.lessons) {
          if (entry.id == lessonId) {
            lesson = entry;
            break;
          }
        }
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
          return ErrorScreen('Ошибка 404', '');
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
            return ErrorScreen('Ошибка 404', '');
          }
        }
      }
    }

    if (parts.isEmpty) {
      // no more parts in path - return course content with tree
      String selectedKey = '';
      if (section.id.isNotEmpty) {
        selectedKey += '$sectionId/';
      }
      if (lesson.id.isNotEmpty) {
        selectedKey += lesson.id;
      }
      Role userRoleForCourse = loggedUser.defaultRole;
      if (userRoleForCourse != Role.ROLE_ADMINISTRATOR) {
        userRoleForCourse = courseEntry.role;
      }
      return CourseScreen(
        user: loggedUser,
        course: courseEntry.course,
        courseData: courseData,
        userRoleForCourse: userRoleForCourse,
        selectedKey: selectedKey.isEmpty? '#' : selectedKey,
      );
    }

    String problemOrReadingId = parts[0];
    parts = parts.sublist(1);

    ProblemData problemData = courseData.findProblemById(problemOrReadingId);
    ProblemMetadata problemMetadata = courseData.findProblemMetadataById(problemOrReadingId);
    TextReading textReading = TextReading();
    for (final entry in lesson.readings) {
      if (entry.id == problemOrReadingId) {
        textReading = entry;
        break;
      }
    }

    if (problemData.id.isNotEmpty) {
      // return problem screen
      if (parts.isEmpty) {
        return CourseProblemScreen(
          user: loggedUser,
          role: courseEntry.role,
          courseUrlPrefix: courseEntry.course.urlPrefix,
          problemId: problemOrReadingId,
        );
      }
      int? submissionId = int.tryParse(parts[0]);
      if (submissionId == null) {
        return ErrorScreen('Ошибка 404', '');
      }
      Role userRoleForCourse = loggedUser.defaultRole;
      if (userRoleForCourse != Role.ROLE_ADMINISTRATOR) {
        userRoleForCourse = courseEntry.role;
      }
      return SubmissionScreen(
        user: loggedUser,
        courseUrlPrefix: courseEntry.course.urlPrefix,
        submissionId: Int64(submissionId),
        course: courseEntry.course,
        role: courseEntry.role,
        courseData: courseData,
      );
    }

    if (textReading.id.isNotEmpty) {
      // return reading screen
      return CourseReadingScreen(user: loggedUser, textReading: textReading);
    }

    // nothing matched - error 404
    return ErrorScreen('Ошибка 404', '');
  }

  ThemeData buildThemeData() {
    return ThemeData(
      colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.blue)
          .copyWith(secondary: Colors.deepPurple),
      fontFamily: 'PT Sans',
    );
  }

  Widget loadingWaitWidget(BuildContext context) {
    return LoadingScreen('', 'Загрузка данных...');
  }

  @override
  Widget build(BuildContext context) {
    MaterialPageRoute onGenerateRoute(RouteSettings settings) {
      return MaterialPageRoute(
          settings: settings,
          builder: (BuildContext context) {
            return generateWidgetForRoute(context, settings);
          }
      );
    }
    String initialRoute = widget.initialSession.initialRoute;
    if (initialRoute.isEmpty) {
      initialRoute = '/';
    }
    MaterialApp app =  MaterialApp(
      title: title,
      theme: buildThemeData(),
      onGenerateRoute: onGenerateRoute,
      initialRoute: initialRoute,
    );
    return app;
  }
}

