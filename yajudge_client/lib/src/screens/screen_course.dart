import 'package:flutter/material.dart';
import '../widgets/course_lessons_tree.dart';
import '../widgets/unified_widgets.dart';
import 'screen_base.dart';

import 'package:path/path.dart' as path;
import 'package:yajudge_common/yajudge_common.dart';


class CourseScreen extends BaseScreen {

  final Course course;
  final CourseData courseData;
  final Section section;
  final Lesson lesson;

  CourseScreen({
    required User user,
    required this.course,
    required this.courseData,
    required this.section,
    required this.lesson,
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

  CourseScreenState(CourseScreen screen): this.screen=screen, super(title: screen.course.name);

  Widget _buildTreeView(context) {
    CourseLessonsTree tree = CourseLessonsTree(
      screen.courseData,
      screen.course.urlPrefix,
      callback: _onLessonPicked,
    );
    return tree;
  }

  void _onLessonPicked(String sectionKey, String lessonKey) {
    String url = screen.course.urlPrefix;
    String subroute = '';
    if (sectionKey.isNotEmpty) {
      subroute += '/' + sectionKey;
    }
    subroute += '/' + lessonKey;
    url += subroute;
    Section section = Section();
    Lesson lesson = Lesson();
    for (Section sectionEntry in screen.courseData.sections) {
      if (sectionKey == sectionEntry.id) {
        section = sectionEntry;
        for (Lesson lessonEntry in section.lessons) {
          if (lessonKey == lessonEntry.id) {
            lesson = lessonEntry;
            break;
          }
        }
        break;
      }
    }
    PageRouteBuilder routeBuilder = PageRouteBuilder(
      settings: RouteSettings(name: url),
      pageBuilder: (_a, _b, _c) {
        return CourseScreen(
          user: widget.loggedUser,
          course: screen.course,
          courseData: screen.courseData,
          section: section,
          lesson: lesson,
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
      width: 300,
      child: treeView,
      padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
    );
    return leftArea;
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

  void _navigateToReading(Section section, Lesson lesson, TextReading reading) {
    String courseUrl = screen.course.urlPrefix;
    String sectionId = section.id;
    String lessonId = lesson.id;
    String readingId = reading.id;
    String location = path.normalize('/$courseUrl/$sectionId/$lessonId/readings/$readingId');
    Navigator.pushNamed(context, location);
  }

  void _navigateToProblem(Section section, Lesson lesson, ProblemData problem) {
    String courseId = screen.course.urlPrefix;
    String sectionId = section.id;
    String lessonId = lesson.id;
    String problemId = problem.id;
    String location = path.normalize('/$courseId/$sectionId/$lessonId/problems/$problemId');
    Navigator.pushNamed(context, location);
  }

  List<Widget> _createReadingsIndex(BuildContext context, Section section, Lesson lesson) {
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
        _navigateToReading(section, lesson, reading);
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

  List<Widget> _createProblemsIndex(BuildContext context, Section section, Lesson lesson) {
    List<Widget> result = List.empty(growable: true);
    if (lesson.problems.isEmpty) {
      return result;
    }
    Text title = Text(
      'Задачи',
      style: Theme.of(context).textTheme.headline6,
    );
    result.add(Padding(child: title, padding: EdgeInsets.fromLTRB(0, 30, 0, 20)));
    for (int i=0; i<lesson.problems.length; i++) {
      ProblemData problem = lesson.problems[i];
      ProblemMetadata metadata = lesson.problemsMetadata[i];
      VoidCallback action = () {
        _navigateToProblem(section, lesson, problem);
      };
      bool problemPassed = false;  // TODO check for passed problems
      bool problemIsRequired = metadata.blocksNextProblems;
      bool problemBlocked = false;
      IconData iconData;
      String secondLineText = '';
      if (problemPassed) {
        iconData = Icons.check_circle;
      } else {
        if (problemBlocked) {
          iconData = Icons.cancel_outlined;
          secondLineText = 'Необходимо решить все предыдущие обязательные задачи';
        } else if (problemIsRequired) {
          secondLineText = 'Это обязательная задача';
          iconData = Icons.error_outline;
        }
        else {
          iconData = Icons.radio_button_off_outlined;
        }
      }
      Icon leadingIcon = Icon(iconData, size: 36,
          color: problemPassed? Theme.of(context).primaryColor : Colors.grey);
      result.add(Padding(
        padding: EdgeInsets.fromLTRB(0, 8, 0, 8),
        child: YCardLikeButton(
          problem.title.isNotEmpty? problem.title : problem.id,
          action,
          leadingIcon: leadingIcon,
          subtitle: secondLineText.isNotEmpty? secondLineText : null,
        ),
      ));
    }
    return result;
  }

  @override
  Widget buildCentralWidget(BuildContext context) {
    if (screen.lesson.id.isEmpty) {
      return Text('');
    }
    List<Widget> items = [];
    items.addAll(_createCommonLessonInformation(context, screen.lesson));
    items.addAll(_createReadingsIndex(context, screen.section, screen.lesson));
    items.addAll(_createProblemsIndex(context, screen.section, screen.lesson));
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        // color: Theme.of(context).backgroundColor.withAlpha(30)
      ),
      constraints: BoxConstraints(
        minWidth: MediaQuery.of(context).size.width - 300,
        minHeight: MediaQuery.of(context).size.height - 46,
      ),
      child: Column(
        children: items,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
      ),
    );
  }

}