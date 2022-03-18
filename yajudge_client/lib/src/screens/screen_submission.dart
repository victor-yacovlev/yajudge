import 'dart:convert';
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:flutter/material.dart';
import 'package:tuple/tuple.dart';
import '../controllers/courses_controller.dart';
import '../widgets/source_view_widget.dart';
import 'screen_course_problem.dart';
import '../controllers/connection_controller.dart';
import 'screen_base.dart';
import '../utils/utils.dart';
import '../widgets/unified_widgets.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'dart:async';
import 'dart:math' as math;

class SubmissionScreen extends BaseScreen {
  final Course? course;
  final Role? role;
  final CourseData? courseData;
  final String courseUrlPrefix;
  final Int64 submissionId;

  SubmissionScreen({
    required User user,
    required this.courseUrlPrefix,
    required this.submissionId,
    this.course,
    this.role,
    this.courseData,
    Key? key
  }) : super(loggedUser: user, key: key) {

  }

  @override
  State<StatefulWidget> createState() => SubmissionScreenState(this);

}

class SubmissionScreenState extends BaseScreenState {

  final SubmissionScreen screen;
  Submission? _submission;
  CourseData? _courseData;
  ProblemData? _problemData;
  ProblemMetadata? _problemMetadata;
  Course? _course;
  Role? _role;
  grpc.ResponseStream<Submission>? _statusStream;

  SubmissionScreenState(this.screen)
      : super(title: 'Посылка ${screen.submissionId}');

  @override
  void initState() {
    super.initState();
    if (screen.courseData != null && screen.course != null && screen.role != null) {
      _courseData = screen.courseData;
      _course = screen.course;
      _role = screen.role;
      _loadSubmission();
    }
    else {
      _loadCourse();
    }
  }

  FutureOr<Null> _handleLoadError(Object error, StackTrace stackTrace) {
    setState(() {
      errorMessage = error;
    });
  }

  void _loadCourse() {
    CoursesController.instance!
        .loadCourseByPrefix(screen.loggedUser, screen.courseUrlPrefix)
        .then((Tuple2<Course,Role> entry) {
          setState(() {
            _course = entry.item1;
            _role = entry.item2;
          });
          _loadCourseData();
        })
        .onError(_handleLoadError);
  }

  void _loadCourseData() {
    CoursesController.instance!
        .loadCourseData(_course!.dataId)
        .then((CourseData courseData) {
          setState(() {
            _courseData = courseData;
          });
          _loadSubmission();
        })
        .onError(_handleLoadError);
  }

  void _loadSubmission() {
    final service = ConnectionController.instance!.submissionsService;
    service.getSubmissionResult(Submission(id: screen.submissionId, course: _course, user: screen.loggedUser))
        .then((submission) {
          _updateSubmission(submission);
          _subscribeToNotifications();
        })
        .onError(_handleLoadError);
  }

  void _updateTitle() {
    setState(() {
      if (_problemData != null) {
        title = 'Посылка ${screen.submissionId}: ${_problemData!.title}';
      }
      else {
        title = 'Посылка ${screen.submissionId}';
      }
    });
  }

  @override
  void dispose() {
    if (_statusStream != null) {
      _statusStream!.cancel();
    }
    super.dispose();
  }

  void _subscribeToNotifications() {
    log.info('subscribing to submission notifications');
    final submissionsService = ConnectionController.instance!.submissionsService;
    final request = Submission(
      id: _submission!.id,
      course: _course,
      user: _submission!.user,
    );
    _statusStream = submissionsService.subscribeToSubmissionResultNotifications(request);
    _statusStream!.listen(
      (event) {
        log.info('got submission update with submission id=${event.id}');
        _updateSubmission(event);
      },
      onError: (error) {
        log.info('submission status subscription error: $error');
        setState(() {
          _statusStream = null;
        });
      },
      cancelOnError: true,
    );
  }

  void _updateSubmission(Submission submission) {
    if (_submission != null && submission.id != _submission!.id) {
      return;
    }
    setState(() {
      if (_submission == null) {
        _submission = submission;
      }
      else {
        _submission = _submission!.copyWith((s) {
          s.status = submission.status;
          s.graderName = submission.graderName;
          s.buildErrorLog = submission.buildErrorLog;
          s.graderScore = submission.graderScore;
          s.styleErrorLog = submission.styleErrorLog;
          s.testResults.clear();
          s.testResults.addAll(submission.testResults);
        });
      }
      _problemData = findProblemById(_courseData!, _submission!.problemId);
      _problemMetadata = findProblemMetadataById(_courseData!, _submission!.problemId);
    });
    _updateTitle();
  }

  void _saveStatementFile(File file) {
    PlatformsUtils.getInstance().saveLocalFile(file.name, file.data);
  }

  List<Widget> buildSubmissionCommonItems(BuildContext context) {
    List<Widget> contents = [];
    if (_submission == null) {
      return [];
    }
    final theme = Theme.of(context);
    final fileHeadStyle = theme.textTheme.headline6!.merge(TextStyle());
    final fileHeadPadding = EdgeInsets.fromLTRB(8, 10, 8, 4);
    final maxFileSizeToShow = 50 * 1024;
    final wrapIntoPadding = (Widget w) {
      return Padding(
          child: w,
          padding: EdgeInsets.fromLTRB(0, 10, 0, 10)
      );
    };
    final makeText = (String text, [Color? color]) {
      return Text(text,
          style: theme.textTheme.bodyText1!.merge(TextStyle(
            fontSize: 16,
            color: color,
          ))
      );
    };
    final addText = (String text, [Color? color]) {
      contents.add(
        wrapIntoPadding(makeText(text, color))
      );
    };
    String statusName = statusMessageText(_submission!.status, false);
    Color statusColor = statusMessageColor(context, _submission!.status);
    String dateSent = formatDateTime(_submission!.timestamp.toInt());
    final whoCanRejudge = [
      Role.ROLE_TEACHER_ASSISTANT, Role.ROLE_TEACHER, Role.ROLE_LECTUER,
    ];
    if (screen.loggedUser.defaultRole==Role.ROLE_ADMINISTRATOR || whoCanRejudge.contains(screen.role)) {
      contents.add(wrapIntoPadding(Row(
        children: [
          wrapIntoPadding(Row(children: [makeText('Статус: '), makeText(statusName, statusColor)])),
          Spacer(),
          ElevatedButton(
            onPressed: _doRejudge,
            child: Text('Перетестировать'),
          )
        ],
      )));
    }
    else {
      addText('Статус: $statusName');
    }
    addText('Отправлена: $dateSent');
    return contents;
  }

  void _doRejudge() {
    final service = ConnectionController.instance!.submissionsService;

    // make cleaned copies of request parameters to prevent
    // HTTP 413 error (Request Entity Too Large)
    final courseForRequest = Course(
      id: _course!.id,
      dataId: _course!.dataId
    );
    final userForRequest = User(id: screen.loggedUser.id);
    final submissionForRequest = Submission(
      id: _submission!.id,
      problemId: _problemData!.id,
    );

    final request = RejudgeRequest(
      user: userForRequest,
      course: courseForRequest,
      problemId: _problemData!.id,
      submission: submissionForRequest,
    );

    final futureResponse = service.rejudge(request);
    futureResponse.then(
      (response) {
        if (response.submission.id == _submission!.id) {
          _updateSubmission(response.submission);
        }
      },
      onError: (error) {
        setState(() {
          errorMessage = error;
        });
      }
    );
  }

  List<Widget> buildSubmissionFileItems(BuildContext context) {
    List<Widget> contents = [];
    if (_submission == null) {
      return [];
    }
    final theme = Theme.of(context);
    final fileHeadStyle = theme.textTheme.headline6!.merge(TextStyle());
    final fileHeadPadding = EdgeInsets.fromLTRB(8, 10, 8, 4);
    final maxFileSizeToShow = 50 * 1024;

    for (File file in _submission!.solutionFiles.files) {
      contents.add(Container(
          padding: fileHeadPadding,
          child: Text(file.name+':', style: fileHeadStyle))
      );
      final button = YCardLikeButton(
          'Скачать', () {
            _saveStatementFile(file);
          },
          leadingIcon: Icon(Icons.arrow_circle_down, color: Colors.grey, size: 36),
      );
      contents.add(Container(child: button, padding: EdgeInsets.fromLTRB(8, 8, 8, 0)));
      String? fileContent;
      if (file.data.length < maxFileSizeToShow) {
        try {
          fileContent = utf8.decode(file.data, allowMalformed: false);
        } catch (_) {
        }
        if (fileContent != null) {
          contents.add(createFilePreview(context, fileContent, true));
        }
        else {
          contents.add(SizedBox(height: 20));
        }
      }

    }

    return contents;
  }

  List<Widget> buildSubmissionErrors(BuildContext context) {
    List<Widget> contents = [];
    if (_submission == null) {
      return [];
    }
    final theme = Theme.of(context);
    final fileHeadStyle = theme.textTheme.headline6!.merge(TextStyle());
    final fileHeadPadding = EdgeInsets.fromLTRB(8, 10, 8, 4);
    final maxFileSizeToShow = 10 * 1024;
    String? fileContent;
    int brokenTestNumber = 0;
    if (_submission!.status == SolutionStatus.COMPILATION_ERROR ) {
      contents.add(Container(
          padding: fileHeadPadding,
          child: Text('Ошибки компиляции:', style: fileHeadStyle))
      );
      fileContent = _submission!.buildErrorLog;
    }
    else if (_submission!.status == SolutionStatus.STYLE_CHECK_ERROR) {
      contents.add(Container(
          padding: fileHeadPadding,
          child: Text('Ошибки форматирования кода:', style: fileHeadStyle))
      );
      fileContent = _submission!.styleErrorLog;
    }
    else if (_submission!.status == SolutionStatus.RUNTIME_ERROR) {
      final brokenTestCase = findFirstBrokenTest();
      fileContent = '=== stdout:\n' + brokenTestCase.stdout + '\n\n=== stderr:\n' + brokenTestCase.stderr;
      brokenTestNumber = brokenTestCase.testNumber.toInt();
      contents.add(Container(
          padding: fileHeadPadding,
          child: Text('Ошибка выполнения на тесте $brokenTestNumber:', style: fileHeadStyle))
      );
    }
    else if (_submission!.status == SolutionStatus.VALGRIND_ERRORS) {
      final brokenTestCase = findFirstBrokenTest();
      fileContent = brokenTestCase.valgrindOutput;
      brokenTestNumber = brokenTestCase.testNumber.toInt();
      contents.add(Container(
          padding: fileHeadPadding,
          child: Text('Ошибки памяти, обнаруженные Valgrind на тесте $brokenTestNumber:', style: fileHeadStyle))
      );
    }
    else if (_submission!.status == SolutionStatus.WRONG_ANSWER) {
      final brokenTestCase = findFirstBrokenTest();
      fileContent = brokenTestCase.checkerOutput;
      brokenTestNumber = brokenTestCase.testNumber.toInt();
      contents.add(Container(
          padding: fileHeadPadding,
          child: Text('Неверный ответ, вывод чекера на тесте $brokenTestNumber:', style: fileHeadStyle))
      );
    }
    if (fileContent != null) {
      if (fileContent.length <= maxFileSizeToShow) {
        contents.add(createFilePreview(context, fileContent, false));
      }
      else {
        contents.add(Text('Вывод слишком большой, отображается только первые ${maxFileSizeToShow} символов'));
        contents.add(createFilePreview(context, fileContent.substring(0, maxFileSizeToShow), false));
      }
    }
    else {
      contents.add(SizedBox(height: 20));
    }
    return contents;
  }

  TestResult findFirstBrokenTest() {
    final brokenStatuses = [
      SolutionStatus.WRONG_ANSWER,
      SolutionStatus.RUNTIME_ERROR,
      SolutionStatus.VALGRIND_ERRORS,
      SolutionStatus.TIME_LIMIT,
    ];
    for (final test in _submission!.testResults) {
      final status = test.status;
      if (brokenStatuses.contains(status)) {
        return test;
      }
    }
    return TestResult();
  }

  Widget createFilePreview(BuildContext context, String data, bool withLineNumbers) {
    return SourceViewWidget(text: data, withLineNumbers: withLineNumbers);
  }

  @override
  Widget buildCentralWidget(BuildContext context) {
    if (_submission == null) {
      return Center(child: Text('Загрузка посылки...'));
    }
    final theme = Theme.of(context);
    List<Widget> contents = [];
    final mainHeadStyle = theme.textTheme.headline4!.merge(TextStyle(color: theme.primaryColor));
    final mainHeadPadding = EdgeInsets.fromLTRB(0, 10, 0, 20);
    final dividerColor = Colors.black38;

    contents.add(Divider(
      height: 40,
      thickness: 2,
      color: dividerColor,
    ));
    contents.addAll(buildSubmissionCommonItems(context));
    contents.add(Divider(
      height: 40,
      thickness: 2,
      color: dividerColor,
    ));

    contents.add(Container(
        padding: mainHeadPadding,
        child: Text('Файлы решения', style: mainHeadStyle))
    );
    contents.addAll(buildSubmissionFileItems(context));

    final submissionErrors = buildSubmissionErrors(context);
    if (submissionErrors.isNotEmpty) {
      contents.add(Divider(
        height: 40,
        thickness: 2,
        color: dividerColor,
      ));
      contents.addAll(submissionErrors);
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

}

const StatusesFull = {
  SolutionStatus.ANY_STATUS_OR_NULL: 'Любой статус',
  SolutionStatus.PENDING_REVIEW: 'Ожидает ревью',
  SolutionStatus.OK: 'Решение зачтено',
  SolutionStatus.PLAGIARISM_DETECTED: 'Подозрение на плагиат',
  SolutionStatus.CODE_REVIEW_REJECTED: 'Отправлено на доработку',
  SolutionStatus.DEFENCE_FAILED: 'Неуспешная защита',
  SolutionStatus.SUBMITTED: 'В очереди на тестирование',
  SolutionStatus.GRADER_ASSIGNED: 'Тестируется',
  SolutionStatus.DISQUALIFIED: 'Дисквалификация',
  SolutionStatus.COMPILATION_ERROR: 'Ошибка компиляции',
  SolutionStatus.STYLE_CHECK_ERROR: 'Ошибка форматирования',
  SolutionStatus.RUNTIME_ERROR: 'Ошибка выполнения',
  SolutionStatus.WRONG_ANSWER: 'Неправильный ответ',
  SolutionStatus.VALGRIND_ERRORS: 'Ошибки Valgrind',
  SolutionStatus.TIME_LIMIT: 'Лимит времени',
};

const StatusesShort = {
  SolutionStatus.ANY_STATUS_OR_NULL: 'ANY',
  SolutionStatus.SUBMITTED: 'NEW',
  SolutionStatus.PENDING_REVIEW: 'PR',
  SolutionStatus.GRADER_ASSIGNED: '...',
  SolutionStatus.DISQUALIFIED: 'DISQ',
  SolutionStatus.COMPILATION_ERROR: 'CE',
  SolutionStatus.STYLE_CHECK_ERROR: 'STY',
  SolutionStatus.RUNTIME_ERROR: 'RE',
  SolutionStatus.WRONG_ANSWER: 'WA',
  SolutionStatus.VALGRIND_ERRORS: 'VLG',
  SolutionStatus.TIME_LIMIT: 'TL',
  SolutionStatus.PLAGIARISM_DETECTED: 'CHEAT?',
  SolutionStatus.CODE_REVIEW_REJECTED: 'REJ',
  SolutionStatus.DEFENCE_FAILED: '!DEF',
};

String statusMessageText(SolutionStatus status, bool shortVariant) {
  // TODO implement i18n for non-Russian languages
  String message = '';

  if (!shortVariant) {
    if (StatusesFull.containsKey(status)) {
      message = StatusesFull[status]!;
    }
    else {
      message = status.name;
    }
  }
  else {
    if (StatusesShort.containsKey(status)) {
      message = StatusesShort[status]!;
    }
    else {
      message = status.name.substring(0, math.min(4, status.name.length)).toUpperCase();
    }
  }
  return message;
}

Color statusMessageColor(BuildContext buildContext, SolutionStatus status) {
  const okStatuses = {
    SolutionStatus.OK,
  };
  const needActionStatuses = {
    SolutionStatus.PLAGIARISM_DETECTED,
    SolutionStatus.PENDING_REVIEW,
    SolutionStatus.ACCEPTABLE,
  };
  const badStatuses = {
    SolutionStatus.CODE_REVIEW_REJECTED,
    SolutionStatus.DEFENCE_FAILED,
    SolutionStatus.WRONG_ANSWER,
    SolutionStatus.RUNTIME_ERROR,
    SolutionStatus.VALGRIND_ERRORS,
    SolutionStatus.TIME_LIMIT,
    SolutionStatus.COMPILATION_ERROR,
    SolutionStatus.STYLE_CHECK_ERROR,
  };
  final theme = Theme.of(buildContext);
  Color color = theme.textTheme.bodyText1!.color!;
  if (okStatuses.contains(status)) {
    color = Colors.green;
  }
  else if (badStatuses.contains(status)) {
    color = theme.errorColor;
  }
  else if (needActionStatuses.contains(status)) {
    color = theme.primaryColor;
  }
  return color;
}
