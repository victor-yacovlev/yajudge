import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_treeview/flutter_treeview.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:tuple/tuple.dart';
import 'screen_course_problem.dart';
import '../controllers/connection_controller.dart';
import '../widgets/unified_widgets.dart';
import 'screen_base.dart';

import 'package:path/path.dart' as path;
import 'package:yajudge_common/yajudge_common.dart';


class CourseScreen extends BaseScreen {

  final Course course;
  final Role userRoleForCourse;
  final CourseData courseData;
  final String selectedKey;
  final double navigatorInitialScrollOffset;
  final CourseStatus? status;
  final grpc.ResponseStream<CourseStatus>? statusStream;

  CourseScreen({
    required User user,
    required this.course,
    required this.courseData,
    required this.selectedKey,
    required this.userRoleForCourse,
    this.navigatorInitialScrollOffset = 0.0,
    this.status,
    this.statusStream,
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
  CourseStatus? _status;
  bool courseStatusIsDirty = false;  // to tree view widget
  grpc.ResponseStream<CourseStatus>? _statusStream;

  late TreeViewController treeViewController;
  late ScrollController treeScrollController;

  CourseScreenState(this.screen):
        super(title: screen.course.name);

  CourseStatus? get courseStatus => _status;

  @override
  void initState() {
    super.initState();
    if (screen.status != null) {
      _status = screen.status;
    }
    if (screen.statusStream != null) {
      _statusStream = screen.statusStream;
    }
    if (_status == null) {
      _checkStatus();
    }
    if (_statusStream == null) {
      _subscribeToNotifications();
    }
    treeScrollController = ScrollController(initialScrollOffset: screen.navigatorInitialScrollOffset);
    _createTreeViewController(screen.selectedKey, _status);
  }

  void _createTreeViewController(String selectedKey, CourseStatus? courseStatus) {
    if (selectedKey.isEmpty) {
      selectedKey = '#';
    }
    final items = _buildTreeViewControllerItems(selectedKey, courseStatus);
    treeViewController = TreeViewController(children: items, selectedKey: selectedKey);
  }

  List<Node> _buildTreeViewControllerItems(String selectedKey, CourseStatus? courseStatus) {
    List<Node> firstLevelNodes = [];
    int firstLevelNumber = 1;
    firstLevelNodes.add(Node(
      key: '#',
      label: 'Общая информация',
      icon: Icons.info_outlined,
    ));
    for (Section section in screen.courseData.sections) {
      String sectionKey = '';
      if (section.id.isNotEmpty) {
        sectionKey = section.id;
      }
      late List<Node> listToAddLessons;
      SectionStatus? sectionStatus;
      int sectionIndex = screen.courseData.sections.indexOf(section);
      sectionStatus = courseStatus!=null? courseStatus.sections[sectionIndex] : null;
      if (section.name.isNotEmpty) {
        List<Node> secondLevelNodes = List.empty(growable: true);
        listToAddLessons = secondLevelNodes;
        int sectionNumber = firstLevelNumber;
        bool expanded = false;
        if (firstLevelNumber == 1) {
          expanded = true;
        }
        else if (selectedKey.isNotEmpty) {
          expanded = selectedKey.startsWith(sectionKey);
        }
        firstLevelNumber ++;
        String sectionPrefix = 'Часть $sectionNumber';
        String sectionTitle = '$sectionPrefix:\n${section.name}';
        IconData? sectionIcon;

        if (sectionStatus != null && sectionStatus.completed) {
          sectionIcon = Icons.done;
        }
        if (sectionStatus != null) {
          int scoreGot = sectionStatus.scoreGot.toInt();
          int scoreMax = sectionStatus.scoreMax.toInt();
          sectionTitle += ' ($scoreGot/$scoreMax)';
        }

        Node sectionNode = Node(
          label: sectionTitle,
          key: sectionKey,
          children: secondLevelNodes,
          expanded: expanded,
          icon: sectionIcon,
        );
        firstLevelNodes.add(sectionNode);
      } else {
        listToAddLessons = firstLevelNodes;
      }
      for (Lesson lesson in section.lessons) {
        int lessonIndex = section.lessons.indexOf(lesson);
        LessonStatus? lessonStatus = sectionStatus!=null? sectionStatus.lessons[lessonIndex] : null;

        String lessonKey = lesson.id;
        if (sectionKey.isNotEmpty) {
          lessonKey = '$selectedKey/$lessonKey';
        }
        IconData? lessonIcon;
        Color? lessonIconColor;
        String lessonTitle = lesson.name;

        if (lessonStatus != null && lessonStatus.completed) {
          lessonIcon = Icons.check;
        }
        else if (lessonStatus!=null && !lessonStatus.blockedByPrevious && lessonStatus.blocksNext) {
          lessonIcon = Icons.arrow_forward_sharp;
        }
        else {
          lessonIcon = Icons.circle_outlined;
          lessonIconColor = Colors.transparent;
        }
        if (lessonStatus != null) {
          int scoreGot = lessonStatus.scoreGot.toInt();
          int scoreMax = lessonStatus.scoreMax.toInt();
          lessonTitle += ' ($scoreGot/$scoreMax)';
        }

        Node lessonNode = Node(
          label: lessonTitle,
          key: lessonKey,
          icon: lessonIcon,
          iconColor: lessonIconColor,
          selectedIconColor: lessonIconColor,
        );
        listToAddLessons.add(lessonNode);
      }
    }
    return firstLevelNodes;
  }
  
  void _checkStatus() {
    final request = CheckCourseStatusRequest(
      user: screen.loggedUser,
      course: screen.course,
    );
    final service = ConnectionController.instance!.progressService;
    final futureCourseStatus = service.checkCourseStatus(request);
    futureCourseStatus.then((CourseStatus status) {
      if (mounted) {
        setState(() {
        errorMessage = '';
      });
      }
      _updateCourseStatus(status);
      if (_statusStream == null) {
        // do timer-based polling in case of streaming not supported
        // by server or some reverse-proxy in http chain
        Future.delayed(Duration(seconds: 5), _checkStatus);
      }
    }).onError((error, stackTrace) {
      if (mounted) {
        setState(() {
        errorMessage = error;
      });
      }
      Future.delayed(Duration(seconds: 5), _checkStatus);
    });
  }

  void _subscribeToNotifications() {
    log.info('subscribing to course status notifications');
    if (errorMessage.isNotEmpty) {
      if (mounted) {
        setState(() {
        errorMessage = '';
      });
      }
    }
    final request = CheckCourseStatusRequest(
      user: screen.loggedUser,
      course: screen.course,
    );
    final service = ConnectionController.instance!.progressService;
    _statusStream = service.subscribeToCourseStatusNotifications(request);
    _statusStream!.listen(
      (CourseStatus event) {
        log.info('got course status event with course.id=${event.course.id}');
        if (mounted) {
          setState(() {
          errorMessage = '';
        });
        }
        _updateCourseStatus(event);
      },
      onError: (error) {
        log.info('course status subscription error: $error');
        if (mounted) {
          setState(() {
          _statusStream = null;
        });
        }
        _checkStatus();  // switch to polling mode
      },
      cancelOnError: true,
    );
  }

  @override
  void dispose() {
    if (_statusStream != null && screen.statusStream == null) {
      _statusStream!.cancel();
    }
    super.dispose();
  }

  void _updateCourseStatus(CourseStatus status) {
    bool empty = status.user.id.toInt()==0 || status.course.id.toInt()==0; 
    if (empty) {
      return; // might be just ping empty message
    }
    if (mounted) {
      setState(() {
      _status = status;
      courseStatusIsDirty = true;
    });
    }
    _createTreeViewController(screen.selectedKey, _status);
  }

  void _onLessonPicked(String key, double initialScrollOffset) {
    String url = screen.course.urlPrefix;
    String subroute = '';
    if (!key.startsWith('#')) {
      subroute = path.normalize(key);
    }
    url += '/$subroute';
    PageRouteBuilder routeBuilder = PageRouteBuilder(
      settings: RouteSettings(name: url),
      pageBuilder: (_, __, ___) {
        return CourseScreen(
          user: widget.loggedUser,
          course: screen.course,
          courseData: screen.courseData,
          selectedKey: key,
          navigatorInitialScrollOffset: initialScrollOffset,
          userRoleForCourse: screen.userRoleForCourse,
          status: _status,
          statusStream: _statusStream,
        );
      },
      transitionDuration: Duration(seconds: 0),
    );
    Navigator.pushReplacement(context, routeBuilder);
  }

  @override
  Widget? buildNavigationWidget(BuildContext context) {
    TreeViewTheme theme;
    theme = _createTreeViewTheme(context);

    TreeView treeView = TreeView(
      primary: false,
      shrinkWrap: true,
      controller: treeViewController,
      theme: theme,
      onNodeTap: _navigationNodeSelected,
    );
    Container container = Container(
      padding: EdgeInsets.fromLTRB(0, 8, 0, 0),
      width: 300,
      constraints: BoxConstraints(
        minHeight: 200,
      ),
      child: treeView,
    );

    SingleChildScrollView scrollView = SingleChildScrollView(
      controller: treeScrollController,
      scrollDirection: Axis.vertical,
      child: container,
    );

    Container leftArea = Container(
      // height: MediaQuery.of(context).size.height - 96,
      width: 500,
      child: scrollView,
      padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
    );
    return leftArea;
  }

  void _navigationNodeSelected(String key) {
    if (key == screen.selectedKey) {
      return;
    }
    setState(() {
      treeViewController = treeViewController.copyWith(selectedKey: key).withExpandToNode(key);
    });
    _onLessonPicked(key, treeScrollController.offset);
  }

  TreeViewTheme _createTreeViewTheme(BuildContext context) {
    TreeViewTheme theme = TreeViewTheme(
      expanderTheme: ExpanderThemeData(
        type: ExpanderType.caret,
        modifier: ExpanderModifier.none,
        position: ExpanderPosition.start,
        size: 20,
      ),
      labelStyle: TextStyle(
        fontSize: 16,
        letterSpacing: 0.3,
      ),
      parentLabelStyle: TextStyle(
        fontSize: 16,
        letterSpacing: 0.1,
      ),
      iconTheme: IconThemeData(
        size: 18,
        color: Colors.grey.shade800,
      ),
      colorScheme: Theme.of(context).colorScheme,
    );
    return theme;
  }

  List<Widget> _createCommonCourseInformation(BuildContext context) {
    List<Widget> result = [];

    final h1Style = Theme.of(context).textTheme.headline4!
        .merge(TextStyle(color: Theme.of(context).textTheme.bodyText1!.color));
    final h2Style = Theme.of(context).textTheme.headline6!;
    final pStyle = Theme.of(context).textTheme.bodyText1!
        .merge(TextStyle(fontSize: 16));

    addText(String text, TextStyle style) {
      double paddingTop = 0;
      double paddingBottom = 0;
      if (style == pStyle) {
        paddingBottom = paddingTop = 10;
      }
      else if (style == h1Style) {
        paddingBottom = 20;
      }
      else if (style == h2Style) {
        paddingTop = 30;
        paddingBottom = 20;
      }
      result.add(
        Padding(
          child: Text(text, style: style),
          padding: EdgeInsets.fromLTRB(0, paddingTop, 0, paddingBottom)
        )
      );
    }

    final descriptionLines = courseDescription.split('\n');
    for (String line in descriptionLines) {
      line = line.trim();
      if (line.isEmpty) {
        continue;
      }
      int headLevel = 0;
      while (line.startsWith('#')) {
        headLevel ++;
        line = line.substring(1);
      }
      line = line.trimLeft();
      TextStyle style = pStyle;
      if (headLevel == 1) {
        style = h1Style;
      }
      else if (headLevel == 2) {
        style = h2Style;
      }
      addText(line, style);
    }

    return result;
  }

  String get courseDescription {
    String template;
    final course = (widget as CourseScreen).course;
    if (course.hasDescription() && course.description.isNotEmpty) {
      template = course.description.trim();
    }
    else {
      template = defaultCourseDescription.trim();
    }
    final sv = <String,String>{};
    if (_status == null) {
      return '';
    }
    sv['problemsRequiredLeft'] = (_status!.problemsRequired-_status!.problemsRequiredSolved).toString();
    sv['problemsRequiredSolved'] = _status!.problemsRequiredSolved.toString();
    sv['problemsTotal'] = _status!.problemsTotal.toString();
    sv['scoreMax'] = _status!.scoreMax.toInt().toString();
    sv['scoreGot'] = _status!.scoreGot.toInt().toString();
    sv['scorePercentage'] = (100*_status!.scoreGot/_status!.scoreMax).round().toString();
    sv['problemsRequired'] = _status!.problemsRequired.toString();
    sv['problemsSolved'] = _status!.problemsSolved.toString();
    sv['problemsLeft'] = (_status!.problemsTotal-_status!.problemsSolved).toString();

    String text = template;
    for (final substitution in sv.entries) {
      final key = substitution.key;
      final value = substitution.value;
      text = text.replaceAll('%$key', value);
    }

    return text;
  }

  static const String defaultCourseDescription = '''
  # О курсе
  Всего в курсе %problemsTotal задач, %problemsRequired из которых являются обязательными.
  Каждая задача оценивается в баллах, в зависимости от сложности.
  Максимальный балл за курс равен %scoreMax.
  ## Статус прохождения
  Решено %problemsSolved задач, из них %problemsRequiredSolved обязательных. 
  Текущий балл %scoreGot (%scorePercentage%).
  Осталось решить %problemsLeft задач, из них %problemsRequiredLeft обязательных.
  ''';

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
    Navigator.pushNamed(context, location).then((_) => _checkStatus());
  }

  void _navigateToProblem(ProblemData problem) {
    String courseUrl = screen.course.urlPrefix;
    String lessonPrefix = screen.selectedKey;
    String problemId = problem.id;
    String location = path.normalize('/$courseUrl/$lessonPrefix/$problemId');
    Navigator.pushNamed(context, location).then((_) => _checkStatus());
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
      action() {
        _navigateToReading(reading);
      }
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
      ProblemStatus? problemStatus;
      if (_status != null) {
        problemStatus = _status!.findProblemStatus(problem.id);
      }
      action() {
        _navigateToProblem(problem);
      }
      bool problemIsRequired = metadata.blocksNextProblems;
      bool problemBlocked = problemStatus!=null && problemStatus.blockedByPrevious;
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
      else if (problemStatus!=null && problemStatus.finalSolutionStatus!=SolutionStatus.ANY_STATUS_OR_NULL) {
        Tuple3<String,IconData,Color> statusView = visualizeSolutionStatus(
            context, problemStatus.finalSolutionStatus, problemStatus.finalGradingStatus,
        );
        String secondLine = statusView.item1;
        if (problemStatus.finalSolutionStatus==SolutionStatus.PENDING_REVIEW && problemIsRequired) {
          secondLine += ', пока можете решать следующие задачи';
        }
        iconData = statusView.item2;
        iconColor = statusView.item3;
        if (secondLineText.isNotEmpty) {
          secondLineText += '. ';
        }
        secondLineText += secondLine;
        if (problemStatus.finalSolutionStatus == SolutionStatus.OK) {
          secondLineText += ' (${problemStatus.scoreGot} из ${problemStatus.scoreMax} баллов)';
        }
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
      Lesson lesson = screen.courseData.findLessonByKey(screen.selectedKey);
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