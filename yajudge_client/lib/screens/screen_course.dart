import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:flutter/widgets.dart';
import 'package:yajudge_client/app.dart';
import 'package:yajudge_client/screens/screen_base.dart';
import 'package:yajudge_client/utils/utils.dart';
import 'package:yajudge_client/widgets/course_lessons_tree.dart';
import 'package:yajudge_client/widgets/unified_widgets.dart';
import 'package:yajudge_client/wsapi/courses.dart';

class CourseScreen extends BaseScreen {
  final String title;
  final String courseId;
  final String courseUrl;
  String? sectionKey;
  String? lessonKey;

  CourseData? courseData;

  CourseScreen(this.title, this.courseId, this.courseUrl, {
    Key? key,
    this.sectionKey,
    this.lessonKey,
    this.courseData,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    CourseScreenState state = CourseScreenState(this);
    return state;
  }
}

class CourseScreenState extends BaseScreenState {

  final CourseScreen screen;
  String? _errorString;
  Lesson? _currentLesson;
  Section? _currentSection;

  CourseScreenState(CourseScreen screen)
      : this.screen=screen, super(title: screen.title);

  void _loadCourseData() {
    AppState.instance.loadCourseData(screen.courseId)
        .then((value) => setState((){ screen.courseData = value; }))
        .onError((err, stackTrace) => setState(() {
          _errorString = err.toString() + '\n' + stackTrace.toString();
        }));
  }

  @override
  void initState() {
    super.initState();
    if (screen.courseData == null) {
      _loadCourseData();
    }
    if (screen.sectionKey != null && screen.lessonKey != null) {
      findLesson();
    }
  }

  Widget _buildTreeView(context) {
    CourseLessonsTree tree = CourseLessonsTree(
      screen.courseData!,
      screen.courseUrl,
      callback: _onLessonPicked,
    );
    return tree;
  }

  void _onLessonPicked(String sectionKey, String lessonKey) {
    String url = '/' + screen.courseUrl;
    if (sectionKey.isNotEmpty) {
      url += '/' + sectionKey;
    } else {
      url += '/_';
    }
    url += '/' + lessonKey;
    PageRouteBuilder routeBuilder = PageRouteBuilder(
      settings: RouteSettings(name: url),
      pageBuilder: (_a, _b, _c) {
        return CourseScreen(screen.title, screen.courseId, screen.courseUrl,
          sectionKey: sectionKey,
          lessonKey: lessonKey,
          courseData: screen.courseData,
        );
      },
      transitionDuration: Duration(seconds: 0),
    );
    Navigator.pushReplacement(context, routeBuilder);
  }

  @override
  Widget? buildNavigationWidget(BuildContext context) {
    if (screen.courseData == null) {
      return null;
    }
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

  @override
  Widget buildCentralWidget(BuildContext context) {
    if (screen.courseData == null) {
      return Center(child: Text(_errorString==null? 'Загружается...' : _errorString!));
    }
    return _createContentArea(context);
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
    String url = '/' + screen.courseUrl + '/' + section.id +
      '/' + lesson.id + '/readings/' + reading.id;
    Navigator.pushNamed(context, url);
  }

  void _navigateToProblem(Section section, Lesson lesson, ProblemData problem) {
    String url = '/' + screen.courseUrl + '/' + section.id +
        '/' + lesson.id + '/problems/' + problem.id + '/statement';
    Navigator.pushNamed(context, url);
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

  void findLesson() {
    if (screen.sectionKey == null || screen.lessonKey == null) {
      return null;
    }
    if (screen.courseData == null) {
      return null;
    }
    for (Section section in screen.courseData!.sections) {
      if (section.id == screen.sectionKey) {
        for (Lesson lesson in section.lessons) {
          if (lesson.id == screen.lessonKey) {
            _currentLesson = lesson;
            _currentSection = section;
            return;
          }
        }
      }
    }
  }

  Widget _createContentArea(BuildContext context) {
    if (_currentLesson == null || _currentSection == null) {
      return Text('');
    }
    List<Widget> items = List.empty(growable: true);
    items.addAll(_createCommonLessonInformation(context, _currentLesson!));
    items.addAll(_createReadingsIndex(context, _currentSection!, _currentLesson!));
    items.addAll(_createProblemsIndex(context, _currentSection!, _currentLesson!));
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