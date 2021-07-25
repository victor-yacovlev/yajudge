import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:simple_html_css/simple_html_css.dart';
import 'package:yajudge_client/screens/screen_base.dart';
import 'package:yajudge_client/wsapi/courses.dart';
import 'package:markdown/markdown.dart' as md;
import '../app.dart';

class CourseProblemScreen extends BaseScreen {
  final String courseId;
  final String problemKey;
  final ProblemData? problemData;
  final String screenState;

  CourseProblemScreen(this.courseId, this.problemKey, this.problemData, this.screenState) : super();

  @override
  State<StatefulWidget> createState() => CourseProblemScreenState();

}

class CourseProblemScreenState extends BaseScreenState {

  late CourseProblemScreen screen;

  ProblemData? _problemData;
  String? _errorString;

  CourseProblemScreenState() : super(title: '');

  void _loadCourseData() {
    AppState.instance.loadCourseData(screen.courseId).then((value) => setState(() {
      CourseData courseData = value;
      _problemData = courseData.findProblemByKey(screen.problemKey);
      if (_problemData == null) {
        _errorString = 'Задача [' + screen.problemKey + '] не найдена';
      }
      this.title = _problemData!.title;
      if (this.title.isEmpty) {
        this.title = _problemData!.id;
      }
    })).onError((err, stackTrace) => setState(() {
      _errorString = err.toString() + '\n' + stackTrace.toString();
    }));
  }

  @override
  void initState() {
    super.initState();
    screen = widget as CourseProblemScreen;
    if (screen.problemData != null) {
      setState(() {
        this._problemData = screen.problemData;
        this.title = screen.problemData!.title;
        if (this.title.isEmpty) {
          this.title = _problemData!.id;
        }
      });
    } else {
      _loadCourseData();
    }
  }

  List<SecondLevelNavigationTab> secondLevelNavigationTabs() {
    Icon statementIcon = Icon(
        Icons.article_outlined
    );
    Icon submissionsIcon = Icon(
        Icons.apps
    );
    Icon discussionIcon = Icon(
        Icons.chat_bubble_outline_rounded
    );
    return [
      SecondLevelNavigationTab('Условие', statementIcon, buildStatementWidget),
      SecondLevelNavigationTab('Посылки', submissionsIcon, buildSubmissionsWidget),
      SecondLevelNavigationTab('Обсуждение', discussionIcon, buildDiscussionsWidget),
    ];
  }

  Widget buildStatementWidget(BuildContext context) {
    List<Widget> contents = List.empty(growable: true);
    if (_problemData == null) {
      contents.add(Text('Загрузка...'));
    }
    if (_errorString != null) {
      contents.add(Text(_errorString!, style: TextStyle(color: Theme.of(context).errorColor)));
    }
    // TODO add common problem information
    if (_problemData != null && _problemData!.statementContentType == 'text/markdown') {
      contents.add(MarkdownBody(
        // TODO make greater look
        styleSheet: MarkdownStyleSheet(textScaleFactor: 1.2),
        selectable: false,
        data: _problemData!.statementText,
        extensionSet: md.ExtensionSet(
          md.ExtensionSet.gitHubFlavored.blockSyntaxes,
          [md.EmojiSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
        ),
      ));
    } else if (_problemData != null && _problemData!.statementContentType == 'text/html') {
      contents.add(HTML.toRichText(context, _problemData!.statementText));
    } else if (_problemData != null) {
      return Text('Content of type '+_problemData!.statementContentType+' is not supported');
    }
    // TODO add problem files download
    Column visible = Column(children: contents);
    return Container(
      padding: EdgeInsets.all(8),
      width: MediaQuery.of(context).size.width,
      constraints: BoxConstraints(
        minHeight: 300,
      ),
      child: visible,
    );
  }

  Widget buildSubmissionsWidget(BuildContext context) {
    return Text('Submissions');
  }

  Widget buildDiscussionsWidget(BuildContext context) {
    return Text('Discussions');
  }


  @override
  Widget buildCentralWidgetCupertino(BuildContext context) {
    return Text('this text should not be visible');
  }

  @override
  Widget buildCentralWidget(BuildContext context) {
    return Container(
      width: MediaQuery.of(context).size.width,
      height: MediaQuery.of(context).size.height-132,
      child: TabBarView(
        children: [
          buildStatementWidget(context),
          buildSubmissionsWidget(context),
          buildDiscussionsWidget(context),
        ]
      )
    );
  }

}