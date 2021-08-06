import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:intl/intl.dart';
import 'package:yajudge_client/screens/screen_base.dart';
import 'package:yajudge_client/utils/utils.dart';
import 'package:yajudge_client/widgets/rich_text_viewer.dart';
import 'package:yajudge_client/widgets/unified_widgets.dart';
import 'package:yajudge_client/wsapi/courses.dart';
import 'package:yajudge_client/wsapi/submissions.dart';
import '../app.dart';

class CourseProblemScreen extends BaseScreen {
  final int courseId;
  final String courseDataId;
  final String problemKey;
  final ProblemData? problemData;
  final ProblemMetadata? problemMetadata;
  final String screenState;

  CourseProblemScreen(this.courseId, this.courseDataId, this.problemKey, this.problemData, this.problemMetadata, this.screenState) : super();

  @override
  State<StatefulWidget> createState() => CourseProblemScreenState();

}

class CourseProblemScreenState extends BaseScreenState {

  late CourseProblemScreen screen;

  CourseData? _courseData;
  ProblemData? _problemData;
  ProblemMetadata? _problemMetadata;
  String? _errorString;
  int? _submissionsLimit;
  int? _nextLimitReset;
  SubmissionList? _submissionList;
  FileSet? _submissionFiles;

  CourseProblemScreenState() : super(title: '');

  void _loadCourseData() {
    AppState.instance.loadCourseData(screen.courseDataId).then((value) => setState(() {
      _courseData = value;
      _problemData = _courseData!.findProblemByKey(screen.problemKey);
      _problemMetadata = _courseData!.findProblemMetadataByKey(screen.problemKey);
      if (_problemData == null || _problemMetadata == null) {
        _errorString = 'Задача [' + screen.problemKey + '] не найдена';
      }
      this.title = _problemData!.title;
      if (this.title.isEmpty) {
        this.title = _problemData!.id;
      }
      _submissionFiles = FileSet.copyOf(_problemData!.solutionFiles!);
      _loadSubmissions();
      _loadSubmissionLimitLeft();
    })).onError((err, stackTrace) => setState(() {
      _errorString = err.toString() + '\n' + stackTrace.toString();
    }));
  }

  void _loadSubmissions() {
    SubmissionFilter filter = SubmissionFilter();
    CourseProblemScreen w = widget as CourseProblemScreen;
    filter.user = AppState.instance.userProfile!;
    filter.course.id = w.courseId;
    filter.problemId = _problemData!.id;
    SubmissionService.instance.getSubmissions(filter).then((value) {
      setState(() {
        _submissionList = value;
      });
    }).onError((error, stackTrace) {
      setState(() {
        _errorString = error.toString() + '\n' + stackTrace.toString();
      });
    });
  }

  void _loadSubmissionLimitLeft() {
    CheckSubmissionsLimitRequest request = CheckSubmissionsLimitRequest();
    CourseProblemScreen w = widget as CourseProblemScreen;
    request.course.id = w.courseId;
    request.course.dataId = w.courseDataId;
    request.problemId = _problemData!.id;
    request.user = AppState.instance.userProfile!;
    SubmissionService.instance.checkSubmissionsCountLimit(request).then((value) {
      setState((){
        _submissionsLimit = value.attemptsLeft;
        _nextLimitReset = value.nextTimeReset;
      });
    }).onError((error, stackTrace) {
      setState(() {
        _errorString = error.toString() + '\n' + stackTrace.toString();
      });
    });
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
        _submissionFiles = FileSet.copyOf(_problemData!.solutionFiles!);
      });
      _loadSubmissions();
      _loadSubmissionLimitLeft();
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
      // SecondLevelNavigationTab('Обсуждение', discussionIcon, buildDiscussionsWidget),
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
      bool hasStatementFiles = _problemData!.statementFiles!.files.isNotEmpty;
      bool hasStyleFiles = _courseData!.codeStyles!=null && _courseData!.codeStyles!.isNotEmpty;
      List<YFile> problemStyleFiles = List.empty(growable: true);
      if (hasStyleFiles) {
        for (YFile solutionFile in _problemData!.solutionFiles!.files) {
          for (CodeStyle codeStyle in _courseData!.codeStyles!) {
            if (solutionFile.name.endsWith(codeStyle.sourceFileSuffix)) {
              if (!problemStyleFiles.contains(codeStyle.styleFile)) {
                problemStyleFiles.add(codeStyle.styleFile..description='Конфиг для проверки стиля кода');
              }
            }
          }
        }
      }
      hasStyleFiles = problemStyleFiles.isNotEmpty;
      if (hasStatementFiles || hasStyleFiles) {
        contents.add(Text('Файлы задания', style: theme.headline5));
        for (YFile file in _problemData!.statementFiles!.files + problemStyleFiles) {
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

  void _pickFileData(YFile file) {
    List<String> suffices = List.empty(growable: true);
    int dotPos = file.name.lastIndexOf('.');
    if (dotPos != -1) {
      suffices.add(file.name.substring(dotPos));
    }
    PlatformsUtils.getInstance().pickLocalFileOpen(suffices).then((LocalFile? value) {
      if (value != null) {
        value.readContents().then((Uint8List bytes) {
          setState(() {
            file.data = bytes.toList();
          });
        });
      }
    });
  }

  void _navigateToSubmission(int submissionId) {

  }

  Widget buildSubmissionsWidget(BuildContext context) {
    List<Widget> contents = List.empty(growable: true);
    if (_errorString != null) {
      contents.add(Text(_errorString!, style: TextStyle(color: Theme.of(context).errorColor)));
    }
    TextTheme theme = Theme.of(context).textTheme;

    if (_courseData != null && _submissionsLimit != null) {
      contents.add(Text('Ограничение на число посылок', style: theme.headline5!));
      contents.add(Text('Количество посылок ограничено, тестируйте решение локально перед отправкой. '));
      contents.add(Text('Вы можете отправлять не более ${_courseData!.maxSubmissionsPerHour} посылок в час. ' ));
      contents.add(Text('Осталось попыток: ${_submissionsLimit!}.'));
      if (_submissionsLimit==0 && _nextLimitReset!=null) {
        String nextReset = formatDateTime(_nextLimitReset!);
        contents.add(Text('Вы сможете отправлять решения после ${nextReset}.'));
      }
      contents.add(SizedBox(height: 20));
    }
    if (_problemData != null) {
      contents.add(Text('Файлы нового решения', style: theme.headline5!));
      for (YFile file in _submissionFiles!.files) {
        String title = file.name;
        String secondLine = '';
        IconData iconData;
        if (file.data.isEmpty) {
          secondLine = 'Файл не выбран - ';
          iconData = Icons.radio_button_off_outlined;
        } else {
          secondLine = '${file.data.length} байт - ';
          iconData = Icons.check_circle;
        }
        if (file.description == null || file.description!.isEmpty) {
          file.description = 'Решение задачи';
        }
        if (file.description != null) {
          secondLine += file.description!;
        }
        Icon leadingIcon = Icon(iconData, size: 36, color: Colors.grey);
        contents.add(Padding(
          padding: EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: YCardLikeButton(
            title,
            () {
              _pickFileData(file);
            },
            leadingIcon: leadingIcon,
            subtitle: secondLine,
          ),
        ));
      }
      contents.add(SizedBox(height: 20));
    }
    if (_submissionList != null && _submissionList!.submissions.isNotEmpty) {
      contents.add(Text('Предыдущие посылки', style: theme.headline5!));
      for (Submission sub in _submissionList!.submissions.reversed) {
        String firstLine = 'ID = ' + sub.id.toString() + ', ' + formatDateTime(sub.timestamp);
        String secondLine = '';
        IconData iconData = Icons.error;
        Color iconColor = Colors.grey;
        switch (sub.status) {
          case SolutionStatus_Submitted:
            iconData = Icons.access_time_rounded;
            secondLine = 'В очереди на тестирование';
            break;
          case SolutionStatus_GradeInProgress:
            iconData = Icons.access_time_rounded;
            secondLine = 'В очереди на тестирование';
            break;
          case SolutionStatus_StyleCheckError:
            iconData = Icons.error_outline;
            secondLine = 'Нарушение форматирования кода';
            break;
          case SolutionStatus_CompilationError:
            iconData = Icons.error_outline;
            secondLine = 'Ошибка компиляции';
            break;
          case SolutionStatus_VeryBad:
            iconData = Icons.error_outline;
            secondLine = 'Не проходят тесты';
            break;
          case SolutionStatus_PendingReview:
            iconData = Icons.access_time_rounded;
            secondLine = 'Решение ожидает проверки';
            break;
          case SolutionStatus_CodeReviewRejected:
            iconData = Icons.error_outline;
            secondLine = 'Необходимо устранить замечания проверяющего';
            break;
          case SolutionStatus_AcceptedForDefence:
            iconData = Icons.check_circle_outline;
            secondLine = 'Решение допущено до защиты';
            break;
          case SolutionStatus_DefenceFailed:
            iconData = Icons.error_outline;
            secondLine = 'Необходимо повторно защитить решение';
            break;
          case SolutionStatus_PlagiarismDetected:
            iconData = Icons.error_outline;
            secondLine = 'Подозрение на плагиат';
            break;
          case SolutionStatus_Disqualified:
            iconData = Icons.error;
            secondLine = 'Решение дисквалифицировано за плагиат';
            iconColor = Theme.of(context).errorColor;
            break;
          case SolutionStatus_OK:
            iconData = Icons.check_circle;
            secondLine = 'Решение зачтено';
            iconColor = Theme.of(context).primaryColor;
            break;
        }
        Icon leadingIcon = Icon(iconData, color: iconColor, size: 36);
        contents.add(Padding(
          padding: EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: YCardLikeButton(
            firstLine,
            () {
              _navigateToSubmission(sub.id);
            },
            leadingIcon: leadingIcon,
            subtitle: secondLine,
          ),
        ));
      }
    }
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

  String formatDateTime(int timestamp) {
    DateFormat formatter = DateFormat('yyyy-MM-dd, HH:mm:ss');
    DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return formatter.format(dateTime);
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
          // buildDiscussionsWidget(context),
        ]
      )
    );
  }

  void _submitSolution() {
    Submission request = Submission();
    screen = widget as CourseProblemScreen;
    request.course.id = screen.courseId;
    request.course.dataId = screen.courseDataId;
    request.user = AppState.instance.userProfile!;
    request.problemId = _problemData!.id;
    request.solutionFiles = _submissionFiles!;
    SubmissionService.instance.submitProblemSolution(request).then((Submission ok) {
      _loadSubmissions();
      _loadSubmissionLimitLeft();
      for (YFile file in _submissionFiles!.files) {
        file.data.clear();
      }
    }).onError((error, stackTrace) {
      setState(() {
        _errorString = error.toString() + '\n' + stackTrace.toString();
      });
    });
  }

  @override
  ScreenSubmitAction? submitAction(BuildContext context) {
    // TODO check for other tabs
    if (_submissionFiles == null) {
      return null;
    }
    if (_submissionsLimit != null && _submissionsLimit! == 0) {
      return null;
    }
    bool allFilesFilled = _submissionFiles!.files.isNotEmpty;
    for (YFile file in _submissionFiles!.files) {
      allFilesFilled &= file.data.isNotEmpty;
    }
    if (!allFilesFilled) {
      return null;
    }
    ScreenSubmitAction submitAction = ScreenSubmitAction(
      title: 'Отправить решение',
      onAction: _submitSolution,
    );
    return submitAction;
  }

  Map<String,TextStyle> _createStyleForTextHtml(BuildContext context) {
    TextTheme theme = Theme.of(context).textTheme;
    return {
      'p': theme.bodyText1!,
      'pre': theme.bodyText1!.merge(TextStyle(fontFamily: 'Courier')),
    };
  }

}