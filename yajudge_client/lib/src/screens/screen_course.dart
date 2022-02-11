import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tuple/tuple.dart';
import 'screen_course_problem.dart';
import '../controllers/connection_controller.dart';
import '../widgets/course_lessons_tree.dart';
import '../widgets/unified_widgets.dart';
import 'screen_base.dart';

import 'package:path/path.dart' as path;
import 'package:yajudge_common/yajudge_common.dart';


class CourseScreen extends BaseScreen {

  final Course course;
  final Role userRoleForCourse;
  final CourseData courseData;
  final CourseStatus courseStatus;
  final String selectedKey;
  final double navigatorInitialScrollOffset;

  CourseScreen({
    required User user,
    required this.course,
    required this.courseData,
    required this.courseStatus,
    required this.selectedKey,
    required this.userRoleForCourse,
    this.navigatorInitialScrollOffset = 0.0,
    Key? key,
  }) : super(loggedUser: user, key: key);

  @override
  State<StatefulWidget> createState() {
    CourseScreenState state = CourseScreenState(this);
    return state;
  }
}

class CourseScreenState extends BaseScreenState {

  final CourseScreen screen;
  late CourseStatus _courseStatus;
  late Timer _statusCheckTimer;

  CourseScreenState(CourseScreen screen):
        this.screen=screen, super(title: screen.course.name) {
    _courseStatus = screen.courseStatus.clone();
  }


  @override
  void initState() {
    super.initState();
    _statusCheckTimer = Timer.periodic(Duration(seconds: 5), (_) {
      if (mounted) {
        // _loadCourseStatus();
      }
    });
  }

  @override
  void dispose() {
    _statusCheckTimer.cancel();
    super.dispose();
  }

  void _updateCourseStatus() {
    final request = CheckCourseStatusRequest(
      user: screen.loggedUser,
      course: screen.course,
    );
    ConnectionController.instance!.submissionsService.checkCourseStatus(request)
    .then((CourseStatus status) {
      setState(() {
        _courseStatus = status;
      });
    });
  }

  Widget _buildTreeView(context) {
    CourseLessonsTree tree = CourseLessonsTree(
      courseData: screen.courseData,
      courseUrl: screen.course.urlPrefix,
      callback: _onLessonPicked,
      courseStatus: _courseStatus,
      selectedKey: screen.selectedKey,
    );
    return tree;
  }

  void _onLessonPicked(String key, double initialScrollOffset) {
    String url = screen.course.urlPrefix;
    String subroute = '';
    if (!key.startsWith('#')) {
      subroute = path.normalize('/$key');
    }
    url += subroute;
    PageRouteBuilder routeBuilder = PageRouteBuilder(
      settings: RouteSettings(name: url),
      pageBuilder: (_a, _b, _c) {
        return CourseScreen(
          user: widget.loggedUser,
          course: screen.course,
          courseData: screen.courseData,
          courseStatus: _courseStatus,
          selectedKey: key,
          navigatorInitialScrollOffset: initialScrollOffset,
          userRoleForCourse: screen.userRoleForCourse,
        );
      },
      transitionDuration: Duration(seconds: 0),
    );
    Navigator.pushReplacement(context, routeBuilder);
  }

  @override
  Widget? buildNavigationWidget(BuildContext context) {
    Widget treeView = Material(
        child: _buildTreeView(context)
    );
    Container leftArea = Container(
      // height: MediaQuery.of(context).size.height - 96,
      width: 500,
      child: treeView,
      padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
    );
    return leftArea;
  }

  List<Widget> _createCommonCourseInformation(BuildContext context) {
    List<Widget> result = [];
    final title = Text('О курсе', textAlign: TextAlign.start,
      style: Theme.of(context).textTheme.headline4!.merge(TextStyle(color: Theme.of(context).textTheme.bodyText1!.color)),
    );
    result.add(Padding(child: title, padding: EdgeInsets.fromLTRB(0, 0, 0, 20)));

    final addText = (String text) {
      result.add(
        Padding(
          child: Text(text,
            style: Theme.of(context).textTheme.bodyText1!.merge(
              TextStyle(
                fontSize: 16,
              )
            ),
          ),
          padding: EdgeInsets.fromLTRB(0, 10, 0, 10)
        )
      );
    };

    final status = screen.courseStatus;

    final descriptionLines = screen.courseData.description.split('\n');
    for (final line in descriptionLines) {
      addText(line);
    }
    addText('Всего в курсе ${status.problemsTotal} задач, ${status.problemsRequired} из которых являются обязательными.');
    addText('Каждая задача оценивается в баллах, в зависимости от сложности. Максимальный балл за курс равен ${status.scoreMax.toInt()}.');

    final titleStatus = Text('Cтатус прохождения', style: Theme.of(context).textTheme.headline6,);
    result.add(Padding(child: titleStatus, padding: EdgeInsets.fromLTRB(0, 30, 0, 20)));
    addText('Решено ${status.problemsSolved} задач, из них ${status.problemsRequiredSolved} обязательных.');
    addText('Текущий балл ${status.scoreGot.toInt()} (${(100*status.scoreGot/status.scoreMax).round()}%)');
    addText('Осталось решить ${status.problemsTotal-status.problemsSolved} задач, из них ${status.problemsRequired-status.problemsRequiredSolved} обязательных.');

    return result;
  }

  List<Widget> _createCommonLessonInformation(BuildContext context, Lesson lesson) {
    List<Widget> result = List.empty(growable: true);
    Text title = Text(
      lesson.name,
      textAlign: TextAlign.start,
      style: Theme.of(context).textTheme.headline4!.merge(
        TextStyle(
          color: Theme.of(context).textTheme.bodyText1!.color
        )
      ),
    );
    result.add(Padding(child: title, padding: EdgeInsets.fromLTRB(0, 0, 0, 20)));
    if (lesson.description.isNotEmpty) {
      Text description = Text(
        lesson.description,
        style: Theme.of(context).textTheme.bodyText1,
        textAlign: TextAlign.start,
      );
      result.add(Padding(child: description, padding: EdgeInsets.fromLTRB(0, 0, 0, 20)));
    }
    return result;
  }

  void _navigateToReading(TextReading reading) {
    String courseUrl = screen.course.urlPrefix;
    String lessonPrefix = screen.selectedKey;
    String readingId = reading.id;
    String location = path.normalize('/$courseUrl/$lessonPrefix/$readingId');
    Navigator.pushNamed(context, location);
  }

  void _navigateToProblem(ProblemData problem) {
    String courseUrl = screen.course.urlPrefix;
    String lessonPrefix = screen.selectedKey;
    String problemId = problem.id;
    String location = path.normalize('/$courseUrl/$lessonPrefix/$problemId');
    Navigator.pushNamed(context, location);
  }

  List<Widget> _createReadingsIndex(BuildContext context, Lesson lesson) {
    List<Widget> result = List.empty(growable: true);
    if (lesson.readings.isEmpty) {
      return result;
    }
    Text title = Text(
      'Материалы для изучения',
      style: Theme.of(context).textTheme.headline6,
    );
    result.add(Padding(child: title, padding: EdgeInsets.fromLTRB(0, 30, 0, 20)));
    for (TextReading reading in lesson.readings) {
      VoidCallback action = () {
        _navigateToReading(reading);
      };
      Icon leadingIcon = Icon(
        Icons.article_outlined,
        color: Colors.grey,
        size: 32,
      );
      result.add(Padding(
        padding: EdgeInsets.fromLTRB(0, 8, 0, 8),
        child: YCardLikeButton(
          reading.title,
          action,
          leadingIcon: leadingIcon,
        ),
      ));
    }
    return result;
  }

  List<Widget> _createProblemsIndex(BuildContext context, Lesson lesson) {
    List<Widget> result = List.empty(growable: true);
    if (lesson.problems.isEmpty) {
      return result;
    }
    Text title = Text('Задачи', style: Theme.of(context).textTheme.headline6);
    result.add(Padding(child: title, padding: EdgeInsets.fromLTRB(0, 30, 0, 20)));
    for (int i=0; i<lesson.problems.length; i++) {
      ProblemData problem = lesson.problems[i];
      ProblemMetadata metadata = lesson.problemsMetadata[i];
      ProblemStatus status = findProblemStatus(_courseStatus, problem.id);
      VoidCallback action = () {
        _navigateToProblem(problem);
      };
      bool problemIsRequired = metadata.blocksNextProblems;
      bool problemBlocked = status.blockedByPrevious;
      IconData iconData;
      Color iconColor = Colors.grey;
      String secondLineText = problemIsRequired? 'Это обязательная задача' : '';
      String disabledHint = '';
      if (problemBlocked) {
        iconData = Icons.cancel_outlined;
        disabledHint = 'Необходимо решить все предыдущие обязательные задачи';
        if (screen.userRoleForCourse != Role.ROLE_STUDENT) {
          disabledHint += '. Но администратор или преподаватель все равно может отправлять решения';
        }
      }
      else if (status.finalSolutionStatus != SolutionStatus.ANY_STATUS_OR_NULL) {
        Tuple3<String,IconData,Color> statusView = visualizeSolutionStatus(context, status.finalSolutionStatus);
        String secondLine = statusView.item1;
        iconData = statusView.item2;
        iconColor = statusView.item3;
        if (secondLineText.isNotEmpty) {
          secondLineText += '. ';
        }
        secondLineText += secondLine;
      }
      else {
        iconData = problemIsRequired? Icons.error_outline : Icons.radio_button_off_outlined;
      }
      Icon leadingIcon = Icon(iconData, size: 36, color: iconColor);
      result.add(Padding(
        padding: EdgeInsets.fromLTRB(0, 8, 0, 8),
        child: YCardLikeButton(
          problem.title.isNotEmpty? problem.title : problem.id,
          action,
          leadingIcon: leadingIcon,
          subtitle: secondLineText.isNotEmpty? secondLineText : null,
          disabled: problemBlocked && screen.loggedUser.defaultRole==Role.ROLE_STUDENT,
          disabledHint: disabledHint,
        ),
      ));
    }
    return result;
  }

  @override
  Widget buildCentralWidget(BuildContext context) {
    List<Widget> items = [];
    if (screen.selectedKey == '#') {
      items.addAll(_createCommonCourseInformation(context));
    }
    else {
      Lesson lesson = findLessonByKey(screen.courseData, screen.selectedKey);
      items.addAll(_createCommonLessonInformation(context, lesson));
      items.addAll(_createReadingsIndex(context, lesson));
      items.addAll(_createProblemsIndex(context, lesson));
    }
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        // color: Theme.of(context).backgroundColor.withAlpha(30)
      ),
      constraints: BoxConstraints(
        minWidth: MediaQuery.of(context).size.width - 500,
        minHeight: MediaQuery.of(context).size.height - 100,
      ),
      child: Column(
        children: items,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
      ),
    );
  }

}