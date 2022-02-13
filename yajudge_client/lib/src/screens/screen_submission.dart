import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:grpc/grpc.dart' as grpc;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tuple/tuple.dart';
import 'screen_course_problem.dart';
import '../controllers/connection_controller.dart';
import 'screen_base.dart';
import '../utils/utils.dart';
import '../widgets/rich_text_viewer.dart';
import '../widgets/unified_widgets.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class SubmissionScreen extends BaseScreen {
  final Course course;
  final Role role;
  final CourseData courseData;
  final ProblemData problemData;
  final ProblemMetadata problemMetadata;
  final Submission submission;

  SubmissionScreen({
    required User user,
    required this.course,
    required this.role,
    required this.courseData,
    required this.problemData,
    required this.problemMetadata,
    required this.submission,
    Key? key
  }) : super(loggedUser: user, key: key) {

  }

  @override
  State<StatefulWidget> createState() => SubmissionScreenState(this);

}

class SubmissionScreenState extends BaseScreenState {

  final SubmissionScreen screen;
  late Submission _submission;
  grpc.ResponseStream<Submission>? _statusStream;

  SubmissionScreenState(this.screen)
      : super(title: 'Посылка ${screen.submission.id}: ${screen.problemData.title}');

  @override
  void initState() {
    super.initState();
    _submission = screen.submission;
    _subscribeToNotifications();
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
      id: _submission.id,
      course: _submission.course,
      user: _submission.user,
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

  void _updateSubmission(Submission event) {
    if (event.id != _submission.id) {
      return;
    }
    setState(() {
      _submission = event;
    });
  }

  void _saveStatementFile(File file) {
    PlatformsUtils.getInstance().saveLocalFile(file.name, file.data);
  }

  List<Widget> buildSubmissionCommonItems(BuildContext context) {
    List<Widget> contents = [];
    final submission = _submission;
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
    final makeText = (String text) {
      return Text(text, style: theme.textTheme.bodyText1!.merge(TextStyle(fontSize: 16)));
    };
    final addText = (String text) {
      contents.add(
        wrapIntoPadding(makeText(text))
      );
    };
    String statusName = submission.status.name;
    String dateSent = formatDateTime(submission.timestamp.toInt());
    final whoCanRejudge = [
      Role.ROLE_TEACHER_ASSISTANT, Role.ROLE_TEACHER, Role.ROLE_LECTUER,
    ];
    if (screen.loggedUser.defaultRole==Role.ROLE_ADMINISTRATOR || whoCanRejudge.contains(screen.role)) {
      contents.add(wrapIntoPadding(Row(
        children: [
          makeText('Статус: $statusName'),
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
    final request = RejudgeRequest(
      user: screen.loggedUser,
      course: screen.course,
      problemId: screen.problemData.id,
      submission: _submission,
    );
    final futureResponse = service.rejudge(request);
    futureResponse.then(
      (response) {
        if (response.submission.id == _submission.id) {
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
    final submission = _submission;
    final theme = Theme.of(context);
    final fileHeadStyle = theme.textTheme.headline6!.merge(TextStyle());
    final fileHeadPadding = EdgeInsets.fromLTRB(8, 10, 8, 4);
    final maxFileSizeToShow = 50 * 1024;

    for (File file in submission.solutionFiles.files) {
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
          contents.add(createFilePreview(context, fileContent));
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
    final submission = _submission;
    final theme = Theme.of(context);
    final fileHeadStyle = theme.textTheme.headline6!.merge(TextStyle());
    final fileHeadPadding = EdgeInsets.fromLTRB(8, 10, 8, 4);
    final maxFileSizeToShow = 10 * 1024;
    String? fileContent;
    if (submission.status == SolutionStatus.COMPILATION_ERROR ) {
      contents.add(Container(
          padding: fileHeadPadding,
          child: Text('Ошибки компиляции:', style: fileHeadStyle))
      );
      fileContent = submission.buildErrorLog;
    }
    else if (submission.status == SolutionStatus.STYLE_CHECK_ERROR) {
      contents.add(Container(
          padding: fileHeadPadding,
          child: Text('Ошибки форматирования кода:', style: fileHeadStyle))
      );
      fileContent = submission.styleErrorLog;
    }
    else if (submission.status == SolutionStatus.RUNTIME_ERROR) {
      contents.add(Container(
          padding: fileHeadPadding,
          child: Text('Ошибка выполнения:', style: fileHeadStyle))
      );
      final brokenTestCase = findFirstBrokenTest();
      fileContent = '=== stdout:\n' + brokenTestCase.stdout + '\n\n=== stderr:\n' + brokenTestCase.stderr;
    }
    else if (submission.status == SolutionStatus.VALGRIND_ERRORS) {
      contents.add(Container(
          padding: fileHeadPadding,
          child: Text('Ошибки памяти, обраруженные Valgrind:', style: fileHeadStyle))
      );
      final brokenTestCase = findFirstBrokenTest();
      fileContent = brokenTestCase.valgrindOutput;
    }
    else if (submission.status == SolutionStatus.WRONG_ANSWER) {
      contents.add(Container(
          padding: fileHeadPadding,
          child: Text('Неверный ответ, вывод чекера:', style: fileHeadStyle))
      );
      final brokenTestCase = findFirstBrokenTest();
      fileContent = brokenTestCase.checkerOutput;
    }
    if (fileContent != null) {
      if (fileContent.length <= maxFileSizeToShow) {
        contents.add(createFilePreview(context, fileContent));
      }
      else {
        contents.add(Text('Вывод слишком большой, отображается только первые ${maxFileSizeToShow} символов'));
        contents.add(createFilePreview(context, fileContent.substring(0, maxFileSizeToShow)));
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
    for (final test in _submission.testResults) {
      final status = test.status;
      if (brokenStatuses.contains(status)) {
        return test;
      }
    }
    return TestResult();
  }

  Widget createFilePreview(BuildContext context, String data) {
    final theme = Theme.of(context);
    final codeTextStyle = theme.textTheme.bodyText1!
        .merge(GoogleFonts.ptMono())
        .merge(TextStyle(letterSpacing: 1.1));
    double screenWidth = MediaQuery.of(context).size.width;
    double horizontalMargins = (screenWidth - 950) / 2;
    if (horizontalMargins < 0) {
      horizontalMargins = 0;
    }
    final contentView = SelectableText(data, style: codeTextStyle);
    final outerBox = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      margin: EdgeInsets.fromLTRB(8, 4, 8, 20),
      padding: EdgeInsets.fromLTRB(8, 8, 8, 8),
      constraints: BoxConstraints(
        minWidth: screenWidth - horizontalMargins * 1,
        minHeight: 50,
      ),
      child: contentView,
    );
    return outerBox;
  }

  @override
  Widget buildCentralWidget(BuildContext context) {
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
