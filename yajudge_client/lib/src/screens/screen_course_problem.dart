import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:tuple/tuple.dart';
import '../controllers/courses_controller.dart';
import 'screen_submission.dart';
import '../controllers/connection_controller.dart';
import 'screen_base.dart';
import '../utils/utils.dart';
import '../widgets/rich_text_viewer.dart';
import '../widgets/unified_widgets.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class CourseProblemScreen extends BaseScreen {
  final String courseUrlPrefix;
  final String problemId;

  CourseProblemScreen({
    required User user,
    required this.courseUrlPrefix,
    required this.problemId,
    Key? key
  }) : super(loggedUser: user, key: key);

  @override
  State<StatefulWidget> createState() => CourseProblemScreenOnePageState(this);

}

class CourseProblemScreenOnePageState extends BaseScreenState {

  final CourseProblemScreen screen;

  Course _course = Course();
  CourseData _courseData = CourseData();
  ProblemData _problemData = ProblemData();
  ProblemMetadata _problemMetadata = ProblemMetadata();

  ProblemStatus _problemStatus = ProblemStatus();
  List<File> _submissionFiles = [];
  grpc.ResponseStream<ProblemStatus>? _statusStream;

  CourseProblemScreenOnePageState(this.screen) : super(title: '');

  @override
  void initState() {
    super.initState();
    statusMessage = 'Загрузка задачи';
    _loadProblemData();
  }

  void _loadProblemData() {
    final coursesController = CoursesController.instance!;
    coursesController.loadCourseByPrefix(screen.loggedUser, screen.courseUrlPrefix)
    .then((Tuple2<Course,Role> courseEntry) {
      setState(() {
        _course = courseEntry.item1;
      });
      coursesController.loadCourseData(courseEntry.item1.dataId)
      .then((CourseData courseData) {
        setState(() {
          _courseData = courseData;
          _problemData = findProblemById(courseData, screen.problemId);
          title = _problemData.title;
          _problemMetadata = findProblemMetadataById(courseData, screen.problemId);
          _submissionFiles = List.from(_problemData.solutionFiles.files);
          clearStatusMessage();
        });
        _subscribeToNotifications();
        _checkStatus();
      })
      .onError((error, _) {
        setState(() {
          statusMessage = '';
          errorMessage = error;
          Future.delayed(Duration(seconds: 5), _loadProblemData);
        });
      });
    })
    .onError((error, _) {
      setState(() {
        statusMessage = '';
        errorMessage = error;
        Future.delayed(Duration(seconds: 5), _loadProblemData);
      });
    });
  }

  void _checkStatus() {
    final submissionsService = ConnectionController.instance!.submissionsService;
    final request = ProblemStatusRequest(
      user: screen.loggedUser,
      course: _course,
      problemId: screen.problemId,
    );
    submissionsService.checkProblemStatus(request)
    .then((ProblemStatus status) {
      setState(() {
        errorMessage = '';
      });
      _updateProblemStatus(status);
      if (_statusStream == null) {
        // do timer-based polling in case of streaming not supported
        // by server or some reverse-proxy in http chain
        Future.delayed(Duration(seconds: 5), _checkStatus);
      }
    })
    .onError((error, _) {
      setState(() {
        errorMessage = error;
      });
      Future.delayed(Duration(seconds: 5), _checkStatus);
    });

  }

  void _subscribeToNotifications() {
    log.info('subscribing to problem status notifications');
    if (errorMessage.isNotEmpty) {
      setState(() {
        errorMessage = '';
      });
    }

    final submissionsService = ConnectionController.instance!.submissionsService;
    final request = ProblemStatusRequest(
      user: screen.loggedUser,
      course: _course,
      problemId: screen.problemId,
    );
    _statusStream = submissionsService.subscribeToProblemStatusNotifications(request);
    _statusStream!.listen(
      (ProblemStatus event) {
        int submissionsCount = event.submissions.length;
        log.info('got problem status event with $submissionsCount existing submissions');
        setState(() {
          errorMessage = '';
        });
        _updateProblemStatus(event);
      },
      onError: (error) {
        log.info('problem status subscription error: $error');
        setState(() {
          _statusStream = null;
        });
        _checkStatus();  // switch to polling mode
      },
      onDone: () {
        log.info('problem status subscription done');
        setState(() {
          errorMessage = '';
          _statusStream = null;
        });
        _subscribeToNotifications();
      },
      cancelOnError: true,
    );
  }

  void _updateProblemStatus(ProblemStatus status) {
    final countLimit = submissionsCountLimitIsValid(status.submissionCountLimit)
      ? status.submissionCountLimit : _problemStatus.submissionCountLimit;
    final newSubmissions = status.submissions.isNotEmpty
      ? status.submissions : _problemStatus.submissions;
    setState(() {
      _problemStatus = ProblemStatus(
        submissionCountLimit: countLimit,
        submissions: newSubmissions,
      );
    });
  }

  @override
  void dispose() {
    if (_statusStream != null) {
      _statusStream!.cancel();
    }
    super.dispose();
  }

  void _saveStatementFile(File file) {
    PlatformsUtils.getInstance().saveLocalFile(file.name, file.data);
  }

  List<Widget> buildStatementItems(BuildContext context) {
    List<Widget> contents = List.empty(growable: true);
    TextTheme theme = Theme.of(context).textTheme;

    // TODO add common problem information
    contents.add(Text('Общая информация', style: theme.headline6));
    String hardeness = '';
    int score = (_problemMetadata.fullScoreMultiplier * 100).toInt();
    if (_problemMetadata.fullScoreMultiplier == 1.0) {
      hardeness = 'обычная, за решение $score баллов';
    }
    else if (_problemMetadata.fullScoreMultiplier == 0.0) {
      hardeness = 'тривиальная, за решение баллы не начисляются';
    }
    else if (_problemMetadata.fullScoreMultiplier < 1.0) {
      hardeness = 'легкая, за решение $score баллов';
    }
    else if (_problemMetadata.fullScoreMultiplier > 1.0) {
      hardeness = 'трудная, за решение $score баллов';
    }
    String problemStatus = '';
    if (_problemMetadata.blocksNextProblems) {
      problemStatus = 'обязательная задача, требуется для прохождения курса дальше';
    } else {
      problemStatus = 'не обязательная задача';
    }
    String actionsOnPassed = '';
    if (_course.noTeacherMode || _problemMetadata.skipCodeReview && _problemMetadata.skipSolutionDefence) {
      actionsOnPassed = 'задача считается решенной, код ревью и защита не требуются';
    } else if (_problemMetadata.skipCodeReview) {
      actionsOnPassed = 'необходимо защитить решение';
    } else if (_problemMetadata.skipSolutionDefence) {
      actionsOnPassed = 'необходимо пройди код ревью';
    } else {
      actionsOnPassed = 'необходимо пройди код ревью и защитить решение';
    }
    contents.add(Text('Сложность: ' + hardeness));
    contents.add(Text('Статус: ' + problemStatus));
    contents.add(Text('После прохождения тестов: ' + actionsOnPassed));
    contents.add(SizedBox(height: 20));
    contents.add(Text('Постановка задачи', style: theme.headline6));
    contents.add(
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        margin: EdgeInsets.fromLTRB(5, 10, 5, 10),
        padding: EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: RichTextViewer(_problemData.statementText, _problemData.statementContentType, theme: theme)
      )
    );
    contents.add(SizedBox(height: 20));
    bool hasStatementFiles = _problemData.statementFiles.files.isNotEmpty;
    bool hasStyleFiles = _courseData.codeStyles.isNotEmpty;
    List<File> problemStyleFiles = List.empty(growable: true);
    if (hasStyleFiles) {
      for (File solutionFile in _problemData.solutionFiles.files) {
        for (CodeStyle codeStyle in _courseData.codeStyles) {
          if (solutionFile.name.endsWith(codeStyle.sourceFileSuffix)) {
            if (!problemStyleFiles.contains(codeStyle.styleFile)) {
              String desc = 'Конфиг для проверки стиля кода, общий для всего курса';
              problemStyleFiles.add(
                  codeStyle.styleFile..description=desc
              );
            }
          }
        }
      }
    }
    hasStyleFiles = problemStyleFiles.isNotEmpty;
    if (hasStatementFiles || hasStyleFiles) {
      contents.add(Text('Файлы задания', style: theme.headline6));
      for (File file in _problemData.statementFiles.files + problemStyleFiles) {
        YCardLikeButton button = YCardLikeButton(file.name, () {
          _saveStatementFile(file);
        }, subtitle: file.description);
        contents.add(Container(
          child: button,
          padding: EdgeInsets.fromLTRB(8, 8, 8, 8),
        ));
      }
    }

    return contents;
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

  void _navigateToSubmission(Submission submission) {
    final service = ConnectionController.instance!.submissionsService;
    service.getSubmissionResult(submission).then((submissionWithData) {
      String currentUrl = ModalRoute.of(context)!.settings.name!;
      String newUrl = '$currentUrl/${submission.id}';
      final routeBuilder = PageRouteBuilder(
          settings: RouteSettings(name: newUrl),
          pageBuilder: (context, animation, secondaryAnimation) {
            return SubmissionScreen(
              user: screen.loggedUser,
              course: _course,
              courseData: _courseData,
              problemData: _problemData,
              problemMetadata: _problemMetadata,
              submission: submissionWithData,
            );
          }
      );
      Navigator.push(context, routeBuilder);
    });
  }

  List<Widget> buildNewSubmissionItems(BuildContext context) {
    List<Widget> contents = [];

    TextTheme theme = Theme.of(context).textTheme;

    int maxSubmissionsPerHour = _courseData.maxSubmissionsPerHour;
    if (_problemData.maxSubmissionsPerHour > 0) {
      maxSubmissionsPerHour = _problemData.maxSubmissionsPerHour;
    }

    if (maxSubmissionsPerHour >= 0) {
      contents.add(Text('Ограничение на число посылок', style: theme.headline6!));
      contents.add(Text('Количество посылок ограничено, тестируйте решение локально перед отправкой. '));
      contents.add(Text('Вы можете отправлять не более $maxSubmissionsPerHour посылок в час. ' ));

      final countLimit = _problemStatus.submissionCountLimit;
      int submissionsLeft = submissionsCountLimitIsValid(countLimit)? countLimit.attemptsLeft : maxSubmissionsPerHour;
      contents.add(Text('Осталось попыток: $submissionsLeft.'));
      if (submissionsLeft == 0) {
        String nextReset = formatDateTime(countLimit.nextTimeReset.toInt());
        contents.add(Text('Вы сможете отправлять решения после $nextReset.'));
      }
      contents.add(SizedBox(height: 20));
    }

    contents.add(Text('Выберете файлы нового решения', style: theme.headline6!));
    for (File file in _submissionFiles) {
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
      secondLine += file.description;

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

    return contents;
  }


  List<Widget> buildSubmissionsItems(BuildContext context) {
    List<Widget> contents = [];

    final submissionsList = _problemStatus.submissions;

    if (submissionsList.isEmpty) {
      contents.add(Text('Посылок пока нет'));
    }
    else {
      List<Submission> submissionsToShow = List.from(submissionsList);
      submissionsToShow.sort((a, b) => b.id.compareTo(a.id));
      for (Submission submission in submissionsToShow) {
        String firstLine = 'ID = ' + submission.id.toString() + ', ' + formatDateTime(submission.timestamp.toInt());
        Tuple3<String,IconData,Color> statusView = visualizeSolutionStatus(context, submission.status);
        String secondLine = statusView.item1;
        IconData iconData = statusView.item2;
        Color iconColor = statusView.item3;

        Icon leadingIcon = Icon(iconData, color: iconColor, size: 36);
        contents.add(Padding(
          padding: EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: YCardLikeButton(
            firstLine,
            () {
              _navigateToSubmission(submission);
            },
            leadingIcon: leadingIcon,
            subtitle: secondLine,
          ),
        ));
      }
    }
    return contents;
  }

  @override
  Widget buildCentralWidget(BuildContext context) {
    final theme = Theme.of(context);
    List<Widget> contents = [];
    final mainHeadStyle = theme.textTheme.headline4!.merge(TextStyle(color: theme.primaryColor));
    final mainHeadPadding = EdgeInsets.fromLTRB(0, 10, 0, 20);
    final dividerColor = Colors.black38;

    contents.add(Container(
        padding: mainHeadPadding,
        child: Text('Условие', style: mainHeadStyle))
    );
    contents.addAll(buildStatementItems(context));
    contents.add(Divider(
      height: 40,
      thickness: 2,
      color: dividerColor,
    ));

    contents.add(Container(
      padding: mainHeadPadding,
      child: Text('Отправка решения', style: mainHeadStyle))
    );
    contents.addAll(buildNewSubmissionItems(context));
    contents.add(_buildSubmitButton(context));
    contents.add(Divider(
      height: 40,
      thickness: 2,
      color: dividerColor,
    ));

    contents.add(Container(
        padding: mainHeadPadding,
        child: Text('Предыдущие посылки', style: mainHeadStyle))
    );
    contents.addAll(buildSubmissionsItems(context));


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

  void _submitSolution() {
    Submission request = Submission(
      course: _course,
      problemId: _problemData.id,
      solutionFiles: FileSet(files: _submissionFiles),
      user: widget.loggedUser,
    );
    ConnectionController.instance!.submissionsService.submitProblemSolution(request).then((_) {
      setState(() {
        for (File file in _submissionFiles) {
          file.data.clear();
        }
        errorMessage = '';
      });
    }).onError((error, _) {
      setState(() {
        errorMessage = error;
      });
    });
  }

  Widget _buildSubmitButton(BuildContext context) {
    String disabledTooltip = whySubmissionFilesNotReadyToSend();
    bool disabled = disabledTooltip.isNotEmpty;

    Color buttonColor;
    MouseCursor mouseCursor = SystemMouseCursors.click;
    if (disabled) {
      // button disabled
      buttonColor = Theme.of(context).disabledColor.withAlpha(35);
      mouseCursor = SystemMouseCursors.basic;
    } else {
      // use default color
      buttonColor = Theme.of(context).primaryColor;
    }
    Widget button = ElevatedButton(
      style: ButtonStyle(
        backgroundColor: MaterialStateProperty.all<Color>(buttonColor),
        mouseCursor: MaterialStateProperty.all<MouseCursor>(mouseCursor),
      ),
      child: Container(
        height: 60,
        padding: EdgeInsets.all(8),
        child: Center(
            child: Text('Отправить решение', style: TextStyle(fontSize: 20, color: Colors.white))
        ),
      ),
      onPressed: disabled? null : _submitSolution,
    );

    return Tooltip(
      message: disabledTooltip,
      child: Container(
        child: Padding(
          child: button,
          padding: EdgeInsets.all(8),
        )
      )
    );
  }

  String whySubmissionFilesNotReadyToSend() {
    if (_submissionFiles.isEmpty) {
      return 'Нечего отправлять';
    }

    final countLimit = _problemStatus.submissionCountLimit;

    if (submissionsCountLimitIsValid(countLimit) && 0==countLimit.attemptsLeft) {
      return 'Исчерпан лимит на количество посылок решения в час';
    }
    bool allFilesFilled = _submissionFiles.isNotEmpty;
    for (File file in _submissionFiles) {
      allFilesFilled &= file.data.isNotEmpty;
    }
    if (!allFilesFilled) {
      return _submissionFiles.length==1
          ? 'Не выбран файл для отправки'
          : 'Не все файлы выбраны для отправки'
      ;
    }
    else {
      return '';
    }
  }

}

Tuple3<String,IconData,Color> visualizeSolutionStatus(BuildContext context, SolutionStatus status) {
  String secondLine = '';
  IconData iconData = Icons.error;
  Color iconColor = Colors.grey;
  switch (status) {
    case SolutionStatus.SUBMITTED:
      iconData = Icons.access_time_rounded;
      secondLine = 'В очереди на тестирование';
      break;
    case SolutionStatus.GRADE_IN_PROGRESS:
      iconData = Icons.access_time_rounded;
      secondLine = 'В очереди на тестирование';
      break;
    case SolutionStatus.GRADER_ASSIGNED:
      iconData = Icons.access_time_rounded;
      secondLine = 'Выполняется тестирование';
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
    case SolutionStatus.VALGRIND_ERRORS:
      iconData = Icons.error_outline;
      secondLine = 'Программа имеет ошибки Valgrind';
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
  return Tuple3(secondLine, iconData, iconColor);
}

String formatDateTime(int timestamp) {
  DateFormat formatter = DateFormat('yyyy-MM-dd, HH:mm:ss');
  DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
  return formatter.format(dateTime);
}