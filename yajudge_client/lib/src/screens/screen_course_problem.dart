import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:tuple/tuple.dart';
import '../controllers/course_content_controller.dart';
import 'screen_submission.dart';
import '../controllers/connection_controller.dart';
import 'screen_base.dart';
import '../utils/utils.dart';
import '../widgets/rich_text_viewer.dart';
import '../widgets/unified_widgets.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:windows1251/windows1251.dart';

class CourseProblemScreen extends BaseScreen {
  final String courseUrlPrefix;
  final String problemId;
  final Role role;

  CourseProblemScreen({
    required User user,
    required this.role,
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
  LessonScheduleSet _scheduleSet = LessonScheduleSet();

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

  @override
  void dispose() {
    _statusStream?.cancel();
    super.dispose();
  }

  void _loadSchedule() {
    final service = ConnectionController.instance!.deadlinesService;
    final request = LessonScheduleRequest(course: _course, user: screen.loggedUser);
    service.getLessonSchedules(request).then((response) {
      if (mounted) {
        setState(() {
          _scheduleSet = response;
        });
      }
    });
  }

  void _loadProblemData() {
    final coursesController = CourseContentController.instance!;
    coursesController.loadCourseByPrefix(screen.loggedUser, screen.courseUrlPrefix)
    .then((Tuple2<Course,Role> courseEntry) {
      setState(() {
        _course = courseEntry.item1;
      });
      coursesController.loadCourseData(courseEntry.item1.dataId)
      .then((CourseData courseData) {
        setState(() {
          _courseData = courseData;
          _problemData = courseData.findProblemById(screen.problemId);
          title = _problemData.title;
          _problemMetadata = courseData.findProblemMetadataById(screen.problemId);
          _submissionFiles = List.from(_problemData.solutionFiles.files);
          clearStatusMessage();
        });
        _subscribeToNotifications();
        _checkStatus();
        _loadSchedule();
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
    final service = ConnectionController.instance!.progressService;
    final request = ProblemStatusRequest(
      user: screen.loggedUser,
      course: _course,
      problemId: screen.problemId,
    );
    service.checkProblemStatus(request)
    .then((ProblemStatus status) {
      setState(() {
        errorMessage = '';
      });
      _updateProblemStatus(status);
    })
    .onError((error, _) {
      setState(() {
        errorMessage = error;
      });
    });

  }

  void _subscribeToNotifications() {
    log.info('subscribing to problem status notifications');
    if (errorMessage.isNotEmpty) {
      setState(() {
        errorMessage = '';
      });
    }

    final service = ConnectionController.instance!.progressService;
    final request = ProblemStatusRequest(
      user: screen.loggedUser,
      course: _course,
      problemId: screen.problemId,
    );
    _statusStream = service.subscribeToProblemStatusNotifications(request);
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
        if (!mounted) {
          return;
        }
        log.info('problem status subscription error: $error');
        setState(() {
          _statusStream = null;
        });
        log.info('switching to fallback problem status checking using long poll');
        Timer(Duration(seconds: 2), _subscribeToNotifications);
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

  void _saveStatementFile(File file) {
    PlatformsUtils.getInstance().saveLocalFile(file.name, file.data);
  }

  TextStyle get mainTextStyle {
    final textTheme = Theme.of(context).textTheme;
    return textTheme.bodyText1!.merge(TextStyle(
      fontSize: 16,
      height: 1.5,
    ));
  }

  List<Widget> buildStatementItems(BuildContext context) {
    List<Widget> contents = [];
    final textTheme = Theme.of(context).textTheme;

    // TODO add common problem information
    contents.add(Text('Общая информация', style: textTheme.headline6));
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
    bool skipReview = _course.disableReview || _problemMetadata.skipCodeReview;
    bool skipDefence = _course.disableDefence || _problemMetadata.skipSolutionDefence;
    if (skipDefence && skipReview) {
      actionsOnPassed = 'задача считается решенной, код ревью и защита не требуются';
    } else if (skipReview) {
      actionsOnPassed = 'необходимо защитить решение';
    } else if (skipDefence) {
      actionsOnPassed = 'необходимо пройди код ревью';
    } else {
      actionsOnPassed = 'необходимо пройди код ревью и защитить решение';
    }

    contents.add(Text('Сложность: $hardeness', style: mainTextStyle));
    contents.add(Text('Статус: $problemStatus', style: mainTextStyle));
    final lesson = _courseData.findEnclosingLessonForProblem(_problemMetadata.id);
    final lessonSchedule = _scheduleSet.findByLesson(lesson.id);
    final deadlines = _problemMetadata.deadlines;
    int penalty = deadlines.softPenalty;
    final tenYearsInSeconds = Duration(days: 10*365).inSeconds;
    if (lessonSchedule.datetime > 0 && deadlines.softDeadline > 0 && deadlines.softDeadline < tenYearsInSeconds && penalty > 0) {
      int deadline = lessonSchedule.datetime.toInt() + deadlines.softDeadline;
      String dateFormat = formatDateTime(deadline);
      String scoreFormat = formatScoreInRussian(penalty);
      contents.add(Text('Мягкий дедлайн: $dateFormat, после этого штраф - минус $scoreFormat в час', style: mainTextStyle));
    }
    if (lessonSchedule.datetime > 0 && deadlines.hardDeadline > 0 && deadlines.hardDeadline < tenYearsInSeconds) {
      int deadline = lessonSchedule.datetime.toInt() + deadlines.hardDeadline;
      String dateFormat = formatDateTime(deadline);
      contents.add(Text('Жесткий дедлайн: $dateFormat, после этого баллы за задачу не начисляются', style: mainTextStyle));
    }
    contents.add(Text('После прохождения тестов: $actionsOnPassed', style: mainTextStyle));

    contents.add(SizedBox(height: 20));
    contents.add(Text('Постановка задачи', style: textTheme.headline6));
    contents.add(
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        margin: EdgeInsets.fromLTRB(5, 10, 5, 10),
        padding: EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: RichTextViewer(_problemData.statementText, _problemData.statementContentType, theme: textTheme)
      )
    );

    contents.add(SizedBox(height: 20));
    contents.add(Text('Ограничения ресурсов', style: textTheme.headline6));
    final courseLimits = _courseData.defaultLimits;
    final problemLimits = _problemData.gradingOptions.limits;
    final limits = courseLimits.mergedWith(problemLimits);
    final executableTarget = _problemData.gradingOptions.executableTarget;
    int memoryTotalLimit = limits.memoryMaxLimitMb.toInt();
    int memoryStackLimit = limits.stackSizeLimitMb.toInt();
    const procLimitDisabledTargets = {
      ExecutableTarget.JavaJar, ExecutableTarget.JavaClass,
    };
    const fdLimitDisabledTargets = {
      ExecutableTarget.JavaJar, ExecutableTarget.JavaClass,
    };
    if (memoryTotalLimit > 0 || memoryStackLimit > 0) {
      List<String> texts = [];
      if (memoryStackLimit > 0) {
        texts.add('$memoryStackLimit Мб (стек)');
      }
      if (memoryTotalLimit > 0) {
        String whatToLimit = 'всего';
        const heapOnlyLimitedTargets = {
          ExecutableTarget.JavaClass, ExecutableTarget.JavaJar,
        };
        if (heapOnlyLimitedTargets.contains(executableTarget)) {
          whatToLimit = 'куча';
        }
        texts.add('$memoryTotalLimit Мб ($whatToLimit)');
      }
      contents.add(Text('Память: ${texts.join(', ')}', style: mainTextStyle));
    }
    int cpuTimeLimit = limits.cpuTimeLimitSec.toInt();
    int timeLimit = limits.realTimeLimitSec.toInt();
    if (cpuTimeLimit > 0 || timeLimit > 0) {
      List<String> texts = [];
      if (cpuTimeLimit > 0) {
        texts.add('$cpuTimeLimit сек. (процессорное)');
      }
      if (timeLimit > 0) {
        texts.add('$timeLimit сек. (астрономическое)');
      }
      contents.add(Text('Время выполнения: ${texts.join(', ')}', style: mainTextStyle));
    }
    int filesLimit = limits.fdCountLimit.toInt();
    if (filesLimit > 0 && !fdLimitDisabledTargets.contains(executableTarget)) {
      contents.add(Text('Максимальное число файловых дескрипторов: $filesLimit', style: mainTextStyle));
    }
    int procsLimit = limits.procCountLimit.toInt();
    if (procsLimit > 0 && !procLimitDisabledTargets.contains(executableTarget)) {
      contents.add(Text('Максимальное число процессов и потоков: $procsLimit', style: mainTextStyle));
    }
    bool allowNetwork = limits.allowNetwork;
    String allowNetworkText = allowNetwork? 'разрешен' : 'запрещен';
    contents.add(Text('Доступ в Интернет: $allowNetworkText', style: mainTextStyle));

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
      contents.add(SizedBox(height: 20));
      contents.add(Text('Файлы задания', style: textTheme.headline6));
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

  Tuple2<String?,String?> decodeFileTextFromBytes(Uint8List bytes) {
    bool utf8Ok = true;
    String? result;
    try {
      result = utf8.decode(bytes, allowMalformed: false);
    }
    catch (e) {
      utf8Ok = false;
    }
    bool w1251ok = true;
    if (!utf8Ok && bytes.contains(13)) {
      // 13 == '\r', so if here are symbols '\r', the text
      // might be created in some Windows text editor
      final decoder = Windows1251Decoder(allowInvalid: false);
      try {
        result = decoder.convert(bytes);
      }
      catch (e) {
        w1251ok = false;
      }
    }
    if (utf8Ok) {
      return Tuple2(result, null);
    }
    else if (!utf8Ok && w1251ok) {
      return Tuple2(null, 'Файл должен быть в кодировке UTF-8, а не Windows-1251');
    }
    else {
      return Tuple2(null, 'Файл должен быть текстовым, а не бинарным');
    }
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
          // check if file is text and size less than 100Kb
          String fileErrorMessage = '';
          String? fileText;
          bool fileOk = bytes.length <= 100*1024;
          if (!fileOk) {
            fileErrorMessage = 'Размер файла не должен превышать 100Кб';
          }
          final fileTextAndError = decodeFileTextFromBytes(bytes);
          if (fileTextAndError.item1 == null) {
            fileOk = false;
            fileErrorMessage = fileTextAndError.item2!;
          }
          setState(() {
            if (fileOk) {
              file.data = utf8.encode(fileTextAndError.item1!);
            }
            else {
              file.data.clear();
              final alertDialog = AlertDialog(
                title: Text('Ошибка загрузки файла'),
                content: Text(fileErrorMessage),
                actions: [
                  TextButton(onPressed: Navigator.of(context).pop, child: Text('OK'))
                ],
              );
              showDialog(context: context, builder: (_) {return alertDialog;});
            }
          });
        });
      }
    });
  }

  void _navigateToSubmission(Submission submission) {
    String currentUrl = ModalRoute.of(context)!.settings.name!;
    String newUrl = '$currentUrl/${submission.id}';
    final submissionScreen = SubmissionScreen(
      courseUrlPrefix: _course.urlPrefix,
      user: screen.loggedUser,
      course: _course,
      role: screen.role,
      submissionId: submission.id,
      courseData: _courseData,
    );
    Widget pageBuilder (context, animation, secondaryAnimation) {
      return submissionScreen;
    }
    final routeBuilder = PageRouteBuilder(
        settings: RouteSettings(name: newUrl),
        pageBuilder: pageBuilder,
    );
    Navigator.push(context, routeBuilder).then((_) => _checkStatus());
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
      contents.add(Text('Количество посылок ограничено, тестируйте решение локально перед отправкой. ', style: mainTextStyle,));
      contents.add(Text('Вы можете отправлять не более $maxSubmissionsPerHour посылок в час. ', style: mainTextStyle));

      final countLimit = _problemStatus.submissionCountLimit;
      int submissionsLeft = submissionsCountLimitIsValid(countLimit)? countLimit.attemptsLeft : maxSubmissionsPerHour;
      contents.add(Text('Осталось попыток: $submissionsLeft.', style: mainTextStyle));
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
      contents.add(Text('Посылок пока нет', style: mainTextStyle));
    }
    else {
      List<Submission> submissionsToShow = List.from(submissionsList);
      submissionsToShow.sort((a, b) => b.id.compareTo(a.id));
      for (Submission submission in submissionsToShow) {
        String firstLine = 'ID = ${submission.id}, ${formatDateTime(submission.datetime.toInt())}';
        var status = submission.status;
        final lessonSchedule = LessonSchedule(); // TODO implement me
        if (_problemMetadata.deadlines.hardDeadlinePassed(lessonSchedule, submission.datetime.toInt())) {
          status = SolutionStatus.HARD_DEADLINE_PASSED;
        }
        Tuple3<String,IconData,Color> statusView = visualizeSolutionStatus(context, status, submission.gradingStatus);
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
        log.severe('while submitting solution: $error');
        if (error is grpc.GrpcError) {
          errorMessage = error;
        }
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

Tuple3<String,IconData,Color> visualizeSolutionStatus(BuildContext context, SolutionStatus status, SubmissionProcessStatus gradingStatus) {
  String secondLine = '';
  IconData iconData = Icons.error;
  Color iconColor = Colors.grey;
  if (gradingStatus == SubmissionProcessStatus.PROCESS_ASSIGNED) {
    return Tuple3('В очереди на тестирование', Icons.access_time_rounded, iconColor);
  }
  if (gradingStatus == SubmissionProcessStatus.PROCESS_QUEUED) {
    return Tuple3('Тестируется', Icons.access_time_rounded, iconColor);
  }
  switch (status) {
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
    case SolutionStatus.SUMMON_FOR_DEFENCE:
      iconData = Icons.error_outline;
      secondLine = 'Необходимо защитить решение';
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
    case SolutionStatus.HARD_DEADLINE_PASSED:
      iconData = Icons.local_fire_department;
      secondLine = 'Решение после дедлайна';
      iconColor = Theme.of(context).errorColor;
      break;
    case SolutionStatus.ANY_STATUS_OR_NULL:
      break;
    case SolutionStatus.CHECK_FAILED:
      break;
  }
  return Tuple3(secondLine, iconData, iconColor);
}

String formatDateTime(int timestamp, {bool withSeconds = false, bool isUtc = true}) {
  DateFormat formatter = DateFormat(withSeconds? 'yyyy-MM-dd, HH:mm:ss' : 'yyyy-MM-dd, HH:mm');
  DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: isUtc);
  DateTime localTime = dateTime.toLocal();
  return formatter.format(localTime);
}

String formatScoreInRussian(int value) {
  if (value % 10 == 1 && value != 11) {
    return '$value балл';
  }
  else if ([2, 3, 4].contains(value % 10) && ![12, 13, 14].contains(value)) {
    return '$value балла';
  }
  else {
    return '$value баллов';
  }
}