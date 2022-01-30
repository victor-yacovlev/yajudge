import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'screen_base.dart';
import '../utils/utils.dart';
import '../widgets/rich_text_viewer.dart';
import '../widgets/unified_widgets.dart';
import 'package:yajudge_common/yajudge_common.dart';
import '../client_app.dart';
import 'package:intl/intl.dart';

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
      String key = screen.problemKey;
      _problemData = findProblemByKey(_courseData!, key);
      _problemMetadata = findProblemMetadataByKey(_courseData!, key);
      if (_problemData == null || _problemMetadata == null) {
        _errorString = 'Задача [' + screen.problemKey + '] не найдена';
      }
      this.title = _problemData!.title;
      if (this.title.isEmpty) {
        this.title = _problemData!.id;
      }
      _submissionFiles = _problemData!.solutionFiles.clone();
      _loadSubmissions();
      _loadSubmissionLimitLeft();
    })).onError((err, stackTrace) => setState(() {
      _errorString = err.toString() + '\n' + stackTrace.toString();
    }));
  }

  void _loadSubmissions() {
    CourseProblemScreen w = widget as CourseProblemScreen;
    User user = AppState.instance.userProfile!;
    Int64 courseId = Int64(w.courseId);
    String problemId = _problemData!.id;
    SubmissionFilter filter = SubmissionFilter(
      course: Course(id: courseId),
      problemId: problemId,
      user: user,
    );

    AppState.instance.submissionsService.getSubmissions(filter).then((value) {
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
    CourseProblemScreen w = widget as CourseProblemScreen;
    User user = AppState.instance.userProfile!;
    Int64 courseId = Int64(w.courseId);
    String courseDataId = w.courseDataId;
    String problemId = _problemData!.id;
    CheckSubmissionsLimitRequest request = CheckSubmissionsLimitRequest(
      course: Course(id: courseId, dataId: courseDataId),
      user: user,
      problemId: problemId,
    );
    AppState.instance.submissionsService..checkSubmissionsCountLimit(request).then((value) {
      setState((){
        _submissionsLimit = value.attemptsLeft;
        _nextLimitReset = value.nextTimeReset.toInt();
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
        _submissionFiles = _problemData!.solutionFiles.clone();
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

  void _saveStatementFile(File file) {
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
        hardeness = 'легкая, коэффициент сложности '+_problemMetadata!.fullScoreMultiplier.toString();
      } else if (_problemMetadata!.fullScoreMultiplier > 1.0) {
        hardeness = 'трудная, коэффициент сложности '+_problemMetadata!.fullScoreMultiplier.toString();
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
      contents.add(
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black12),
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          margin: EdgeInsets.fromLTRB(5, 10, 5, 10),
          padding: EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: RichTextViewer(_problemData!.statementText, _problemData!.statementContentType, theme: theme)
        )
      );
      contents.add(SizedBox(height: 20));
      bool hasStatementFiles = _problemData!.statementFiles.files.isNotEmpty;
      bool hasStyleFiles = _courseData!.codeStyles!=null && _courseData!.codeStyles.isNotEmpty;
      List<File> problemStyleFiles = List.empty(growable: true);
      if (hasStyleFiles) {
        for (File solutionFile in _problemData!.solutionFiles.files) {
          for (CodeStyle codeStyle in _courseData!.codeStyles) {
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
        for (File file in _problemData!.statementFiles.files + problemStyleFiles) {
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
    Column visible = Column(children: contents, crossAxisAlignment: CrossAxisAlignment.start);
    double screenWidth = MediaQuery.of(context).size.width;
    double horizontalMargins = (screenWidth - 950) / 2;
    if (horizontalMargins < 0) {
      horizontalMargins = 0;
    }
    return SingleChildScrollView(
      child: Container(
        child: visible,
        padding: EdgeInsets.fromLTRB(0, 10, 0, 10),
        margin: EdgeInsets.fromLTRB(horizontalMargins, 20, horizontalMargins, 20),
        constraints: BoxConstraints(
          minHeight: 300,
        ),
      )
    );
  }

  void _pickFileData(File file) {
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
      for (File file in _submissionFiles!.files) {
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
        if (file.description.isEmpty) {
          file.description = 'Решение задачи';
        }
        if (file.description != null) {
          secondLine += file.description;
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
        String firstLine = 'ID = ' + sub.id.toString() + ', ' + formatDateTime(sub.timestamp.toInt());
        String secondLine = '';
        IconData iconData = Icons.error;
        Color iconColor = Colors.grey;
        switch (sub.status) {
          case SolutionStatus.SUBMITTED:
            iconData = Icons.access_time_rounded;
            secondLine = 'В очереди на тестирование';
            break;
          case SolutionStatus.GRADE_IN_PROGRESS:
            iconData = Icons.access_time_rounded;
            secondLine = 'В очереди на тестирование';
            break;
          case SolutionStatus.STYLE_CHECK_ERROR:
            iconData = Icons.error_outline;
            secondLine = 'Нарушение форматирования кода';
            break;
          case SolutionStatus.COMPILATION_ERROR:
            iconData = Icons.error_outline;
            secondLine = 'Ошибка компиляции';
            break;
          case SolutionStatus.RUNTIME_ERROR:
            iconData = Icons.error_outline;
            secondLine = 'Программа упала на одном из тестов';
            break;
          case SolutionStatus.TIME_LIMIT:
            iconData = Icons.error_outline;
            secondLine = 'Программа выполнялась слишком долго на одном из тестов';
            break;
          case SolutionStatus.WRONG_ANSWER:
            iconData = Icons.error_outline;
            secondLine = 'Неправильный ответ в одном из тестов';
            break;
          case SolutionStatus.PENDING_REVIEW:
            iconData = Icons.access_time_rounded;
            secondLine = 'Решение ожидает проверки';
            break;
          case SolutionStatus.CODE_REVIEW_REJECTED:
            iconData = Icons.error_outline;
            secondLine = 'Необходимо устранить замечания проверяющего';
            break;
          case SolutionStatus.ACCEPTABLE:
            iconData = Icons.check_circle_outline;
            secondLine = 'Решение допущено до защиты';
            break;
          case SolutionStatus.DEFENCE_FAILED:
            iconData = Icons.error_outline;
            secondLine = 'Необходимо повторно защитить решение';
            break;
          case SolutionStatus.PLAGIARISM_DETECTED:
            iconData = Icons.error_outline;
            secondLine = 'Подозрение на плагиат';
            break;
          case SolutionStatus.DISQUALIFIED:
            iconData = Icons.error;
            secondLine = 'Решение дисквалифицировано за плагиат';
            iconColor = Theme.of(context).errorColor;
            break;
          case SolutionStatus.OK:
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
              _navigateToSubmission(sub.id.toInt());
            },
            leadingIcon: leadingIcon,
            subtitle: secondLine,
          ),
        ));
      }
    }
    Column visible = Column(children: contents, crossAxisAlignment: CrossAxisAlignment.start);
    double screenWidth = MediaQuery.of(context).size.width;
    double horizontalMargins = (screenWidth - 950) / 2;
    if (horizontalMargins < 0) {
      horizontalMargins = 0;
    }
    return SingleChildScrollView(
        child: Container(
          child: visible,
          padding: EdgeInsets.fromLTRB(0, 10, 0, 10),
          margin: EdgeInsets.fromLTRB(horizontalMargins, 20, horizontalMargins, 20),
          constraints: BoxConstraints(
            minHeight: 300,
          ),
        )
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
    screen = widget as CourseProblemScreen;
    Submission request = Submission(
      course: Course(id: Int64(screen.courseId), dataId: screen.courseDataId),
      problemId: _problemData!.id,
      solutionFiles: _submissionFiles,
      user: AppState.instance.userProfile!,
    );
    AppState.instance.submissionsService.submitProblemSolution(request).then((Submission ok) {
      _loadSubmissions();
      _loadSubmissionLimitLeft();
      for (File file in _submissionFiles!.files) {
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
    for (File file in _submissionFiles!.files) {
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