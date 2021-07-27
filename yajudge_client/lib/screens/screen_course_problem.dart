import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:simple_html_css/simple_html_css.dart';
import 'package:yajudge_client/screens/screen_base.dart';
import 'package:yajudge_client/utils/utils.dart';
import 'package:yajudge_client/widgets/rich_text_viewer.dart';
import 'package:yajudge_client/widgets/unified_widgets.dart';
import 'package:yajudge_client/wsapi/courses.dart';
import 'package:markdown/markdown.dart' as md;
import '../app.dart';

class CourseProblemScreen extends BaseScreen {
  final String courseId;
  final String problemKey;
  final ProblemData? problemData;
  final ProblemMetadata? problemMetadata;
  final String screenState;

  CourseProblemScreen(this.courseId, this.problemKey, this.problemData, this.problemMetadata, this.screenState) : super();

  @override
  State<StatefulWidget> createState() => CourseProblemScreenState();

}

class CourseProblemScreenState extends BaseScreenState {

  late CourseProblemScreen screen;

  ProblemData? _problemData;
  ProblemMetadata? _problemMetadata;
  String? _errorString;

  CourseProblemScreenState() : super(title: '');

  void _loadCourseData() {
    AppState.instance.loadCourseData(screen.courseId).then((value) => setState(() {
      CourseData courseData = value;
      _problemData = courseData.findProblemByKey(screen.problemKey);
      _problemMetadata = courseData.findProblemMetadataByKey(screen.problemKey);
      if (_problemData == null || _problemMetadata == null) {
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
        Icons.rule
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

  void _saveStatementFile(YFile file) {
    PlatformsUtils.getInstance().saveLocalFile(file.name, file.data);
  }

  Widget buildStatementWidget(BuildContext context) {
    List<Widget> contents = List.empty(growable: true);
    TextTheme theme = Theme.of(context).textTheme;
    if (_problemData == null) {
      contents.add(Text('Загрузка...'));
    }
    if (_errorString != null) {
      contents.add(Text(_errorString!, style: TextStyle(color: Theme.of(context).errorColor)));
    }
    if (_problemData!=null && _problemMetadata!=null) {
    // TODO add common problem information
      contents.add(Text('Общая информация', style: theme.headline5));
      String hardeness = '';
      if (_problemMetadata!.fullScoreMultiplier == 1.0) {
        hardeness = 'обычная';
      } else if (_problemMetadata!.fullScoreMultiplier < 1.0) {
        hardeness = 'легкая, в оценку войдет с весом '+_problemMetadata!.fullScoreMultiplier.toString();
      } else if (_problemMetadata!.fullScoreMultiplier > 1.0) {
        hardeness = 'сложная, в оценку войдет с весом '+_problemMetadata!.fullScoreMultiplier.toString();
      }
      String problemStatus = '';
      if (_problemMetadata!.blocksNextProblems) {
        problemStatus = 'обязательная задача, требуется для прохождения курса дальше';
      } else {
        problemStatus = 'не обязательная задача';
      }
      String actionsOnPassed = '';
      if (_problemMetadata!.skipCodeReview && _problemMetadata!.skipSolutionDefence) {
        actionsOnPassed = 'задача считается решенной, код ревью и защита не требуются';
      } else if (_problemMetadata!.skipCodeReview) {
        actionsOnPassed = 'необходимо защитить решение';
      } else if (_problemMetadata!.skipSolutionDefence) {
        actionsOnPassed = 'необходимо пройди код ревью';
      } else {
        actionsOnPassed = 'необходимо пройди код ревью и защитить решение';
      }
      contents.add(Text('Сложность: ' + hardeness));
      contents.add(Text('Статус: ' + problemStatus));
      contents.add(Text('После прохождения тестов: ' + actionsOnPassed));
      contents.add(SizedBox(height: 20));
      contents.add(Text('Условие', style: theme.headline5));
      contents.add(RichTextViewer(_problemData!.statementText, _problemData!.statementContentType, theme: theme));
      contents.add(SizedBox(height: 20));
      if (_problemData!.statementFiles.files.isNotEmpty) {
        contents.add(Text('Файлы задания', style: theme.headline5));
        for (YFile file in _problemData!.statementFiles.files) {
          YCardLikeButton button = YCardLikeButton(file.name, () {
            _saveStatementFile(file);
          }, subtitle: file.description);
          contents.add(Container(
            child: button,
            padding: EdgeInsets.fromLTRB(8, 8, 8, 8),
          ));
        }
      }
    }
    // TODO add problem files download
    Column visible = Column(children: contents, crossAxisAlignment: CrossAxisAlignment.start);
    return Container(
      padding: EdgeInsets.fromLTRB(0, 10, 0, 10),
      width: MediaQuery.of(context).size.width,
      constraints: BoxConstraints(
        minHeight: 300,
      ),
      child: SingleChildScrollView(child: visible),
    );
  }

  Widget buildSubmissionsWidget(BuildContext context) {
    return Text('Submissions');
  }

  Widget buildDiscussionsWidget(BuildContext context) {
    return Text('Discussions');
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

  Map<String,TextStyle> _createStyleForTextHtml(BuildContext context) {
    TextTheme theme = Theme.of(context).textTheme;
    return {
      'p': theme.bodyText1!,
      'pre': theme.bodyText1!.merge(TextStyle(fontFamily: 'Courier')),
    };
  }

}