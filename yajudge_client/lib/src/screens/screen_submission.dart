import 'dart:convert';
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:flutter/material.dart';
import 'package:protobuf/protobuf.dart';
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
  }) : super(loggedUser: user, key: key);

  @override
  State<StatefulWidget> createState() => SubmissionScreenState(this);

}

enum WhatToRejudge {
  thisSubmission,
  brokenSubmissions,
  allSubmissions,
}

class SubmissionScreenState extends BaseScreenState {

  final SubmissionScreen screen;
  Submission? _submission;
  List<SubmissionListEntry> _submissionsHistory = [];
  CourseData? _courseData;
  ProblemData? _problemData;
  ProblemMetadata? _problemMetadata;
  Course? _course;
  grpc.ResponseStream<Submission>? _statusStream;
  WhatToRejudge _whatToRejudge = WhatToRejudge.thisSubmission;
  late final LineCommentController _lineCommentController;
  late final TextEditingController _globalCommentController;
  ReviewHistory? _reviewHistory;
  bool _hasUnsavedChanges = false;

  SubmissionScreenState(this.screen)
      : super(title: 'Посылка ${screen.submissionId}');

  @override
  void initState() {
    super.initState();
    _lineCommentController = LineCommentController(editable: canMakeReview());
    _lineCommentController.addListener(_checkForUnsavedChanges);
    _globalCommentController = TextEditingController();
    _globalCommentController.addListener(_checkForUnsavedChanges);
    if (screen.courseData != null && screen.course != null && screen.role != null) {
      _courseData = screen.courseData;
      _course = screen.course;
      _loadSubmission(true);
      _loadCodeReviews();
    }
    else {
      _loadCourse();
    }
  }

  CodeReview get currentStateCodeReview {
    final globalMessage = _globalCommentController.text.trim();
    final lineComments = _lineCommentController.comments;
    return CodeReview(
      submissionId: screen.submissionId,
      globalComment: globalMessage,
      lineComments: lineComments
    ).deepCopy();
  }

  void _checkForUnsavedChanges() {
    setState(() {
      final current = currentStateCodeReview;
      final saved = _reviewHistory?.findBySubmissionId(screen.submissionId) ?? CodeReview();
      log.info('checking for unsaved comment changes');
      log.info('current state: ${current.debugInfo()}');
      log.info('saved state: ${saved.debugInfo()}');
      _hasUnsavedChanges = canSaveReviewChanges();
      if (_hasUnsavedChanges) {
        log.info('has unsaved comment changes');
      }
    });
  }

  void _loadCourse() {
    CoursesController.instance!
        .loadCourseByPrefix(screen.loggedUser, screen.courseUrlPrefix)
        .then((Tuple2<Course,Role> entry) {
          setState(() {
            _course = entry.item1;
          });
          _loadCourseData();
        }).onError((Object error, StackTrace stackTrace) {
      log.warning('got error while loading course: $error');
      setState(() {
        errorMessage = error;
      });
    });
  }

  void _loadCourseData() {
    CoursesController.instance!
        .loadCourseData(_course!.dataId)
        .then((CourseData courseData) {
          setState(() {
            _courseData = courseData;
          });
          _loadSubmission(true);
          _loadCodeReviews();
        })
        .onError((Object error, StackTrace stackTrace) {
      log.warning('got error while loading course data: $error');
      setState(() {
        errorMessage = error;
      });
    });
  }

  void _loadSubmission(bool subscribe) {
    final service = ConnectionController.instance!.submissionsService;
    service.getSubmissionResult(Submission(id: screen.submissionId, course: _course, user: screen.loggedUser))
        .then((submission) {
          _updateSubmission(submission);
          _loadSubmissionsHistory();
          if (subscribe) {
            _subscribeToNotifications();
          }
        })
        .onError((Object error, StackTrace stackTrace) {
      log.warning('got error while loading submission result: $error');
      setState(() {
        errorMessage = error;
      });
    });
  }

  void _loadSubmissionsHistory() {
    if (_submission == null) {
      return;
    }
    final service = ConnectionController.instance!.submissionsService;
    final query = SubmissionListQuery(
      showMineSubmissions: true,
      courseId: _submission!.course.id,
      problemIdFilter: _submission!.problemId,
      nameQuery: '${_submission!.user.id}',
    );
    service.getSubmissionList(query).then(_updateSubmissionsHistory);
  }

  void _loadCodeReviews() {
    final service = ConnectionController.instance!.codeReviewService;
    final submissionId = screen.submissionId;
    final course = _course!;
    final courseId = course.id;
    log.info('requesting code review history for submission $submissionId in course $courseId');
    final request = Submission(id: submissionId, course: course);
    service.getReviewHistory(request).then(_updateCodeReviews)
        .onError((Object error, StackTrace stackTrace) {
      log.warning('got error while loading code review history: $error');
      setState(() {
        errorMessage = error;
      });
    });
  }

  void _updateCodeReviews(ReviewHistory history) {
    setState(() {
      log.info('got review history of size ${history.reviews.length}');
      _reviewHistory = history.deepCopy();
      _reviewHistory!.reviews.sort((a, b) => a.datetime.compareTo(b.datetime));
      CodeReview? currentReview = _reviewHistory!.findBySubmissionId(screen.submissionId);
      if (currentReview != null) {
        log.info('current review global comment: ${currentReview.globalComment}');
        _globalCommentController.text = currentReview.globalComment;
        log.info('current review has ${currentReview.lineComments.length} line comments');
        _lineCommentController.comments = currentReview.lineComments;
        _hasUnsavedChanges = canSaveReviewChanges();
      }
    });
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

  void _updateSubmissionsHistory(SubmissionListResponse response) {
    setState(() {
      _submissionsHistory = response.entries;
      final visibleItems = _submissionsHistory.map(submissionListEntryToString);
      final entriesString = visibleItems.join(', ');
      log.info('Got submissions history: [$entriesString]');
    });
  }

  static String submissionListEntryToString(SubmissionListEntry entry) {
    final id = entry.submissionId.toInt();
    final status = entry.status;
    final gradingStatus = entry.gradingStatus;
    final statusName = statusMessageText(status, gradingStatus, '', true);
    return '$id ($statusName)';
  }

  @override
  void dispose() {
    _statusStream?.cancel();
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
        if (!mounted) {
          return;
        }
        log.info('submission status subscription error: $error');
        setState(() {
          _statusStream = null;
        });
        Timer(Duration(seconds: 3), _subscribeToNotifications);
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
        _submission = submission.deepCopy();
      }
      else {
        if (submission.status != SolutionStatus.ANY_STATUS_OR_NULL) {
          _submission!.status = submission.status;
        }
        _submission!.gradingStatus = submission.gradingStatus;
        _submission!.graderName = submission.graderName;
        _submission!.buildErrorLog = submission.buildErrorLog;
        _submission!.graderScore = submission.graderScore;
        _submission!.styleErrorLog = submission.styleErrorLog;
        _submission!.testResults.clear();
        _submission!.testResults.addAll(submission.testResults);
      }
      _problemData = _courseData!.findProblemById(_submission!.problemId);
      _problemMetadata = _courseData!.findProblemMetadataById(submission.problemId);
    });
    _updateTitle();
  }

  void _saveStatementFile(File file) {
    PlatformsUtils.getInstance().saveLocalFile(file.name, file.data);
  }

  List<Widget> buildReviewerCommentItems(BuildContext context) {
    List<Widget> contents = [];
    if (_reviewHistory == null) {
      return [];
    }
    final codeReview = _reviewHistory!.findBySubmissionId(screen.submissionId);
    if (codeReview==null) {
      return [];
    }

    final theme = Theme.of(context);
    final headStyle = theme.textTheme.headline6!.merge(TextStyle());
    final headPadding = EdgeInsets.fromLTRB(8, 4, 8, 4);
    final mainPadding = EdgeInsets.fromLTRB(8, 4, 8, 4);

    final globalReview = codeReview.globalComment.trim();
    if (globalReview.isNotEmpty) {
      contents.add(Container(
          padding: headPadding,
          child: Text('Общий комментарий', style: headStyle))
      );
      contents.add(Container(
          padding: mainPadding,
          child: Text(globalReview))
      );
    }

    final fileLines = <String,Set<int>>{};
    for (final lineComment in codeReview.lineComments) {
      final fileName = lineComment.fileName;
      Set<int> numbers = {};
      if (fileLines.containsKey(fileName)) {
        numbers = fileLines[fileName]!;
      }
      numbers.add(lineComment.lineNumber+1);
      fileLines[fileName] = numbers;
    }
    for (final fileName in fileLines.keys) {
      contents.add(Container(
          padding: headPadding,
          child: Text('Файл $fileName', style: headStyle))
      );
      final lineNumbers = List.of(fileLines[fileName]!);
      lineNumbers.sort();
      String text = 'Замечания в строк${lineNumbers.length==1? 'е' : 'ах'} ';
      if (lineNumbers.length == 1) {
        text += '${lineNumbers.single}';
      } else {
        for (int i=0; i<lineNumbers.length; i++) {
          if (i > 0 && i<lineNumbers.length-1) {
            text += ', ';
          }
          else if (i == lineNumbers.length-1) {
            text += ' и ';
          }
          text += '${lineNumbers[i]}';
        }
      }
      contents.add(Container(
          padding: mainPadding,
          child: Text(text))
      );
    }
    return contents;
  }

  void manualStatusChange(SolutionStatus? newStatus) {
    if (newStatus == null) {
      return;
    }
  }

  void showChangeStatusDialog(BuildContext context, SolutionStatus currentStatus) {
    List<SolutionStatus> statuses = [
      SolutionStatus.OK, SolutionStatus.SUMMON_FOR_DEFENCE,
      SolutionStatus.PENDING_REVIEW, SolutionStatus.CODE_REVIEW_REJECTED,
      SolutionStatus.PLAGIARISM_DETECTED, SolutionStatus.DISQUALIFIED,
      SolutionStatus.COMPILATION_ERROR, SolutionStatus.WRONG_ANSWER,
      SolutionStatus.TIME_LIMIT, SolutionStatus.VALGRIND_ERRORS,
      SolutionStatus.STYLE_CHECK_ERROR,
    ];
    final theme = Theme.of(context);
    Text makeText(String text, [Color? color]) {
      return Text(text,
          style: theme.textTheme.bodyText1!.merge(TextStyle(
            fontSize: 16,
            color: color,
          ))
      );
    }
    final newStatus = showDialog<SolutionStatus>(context: context, builder: (BuildContext context) {
      return SimpleDialog(
        title: Text('Изменить статус', style: theme.textTheme.headline5),
        children: statuses.map((status) {
          final statusName = statusMessageText(status, SubmissionGradingStatus.processed, '', false);
          final statusColor = statusMessageColor(context, status);
          return SimpleDialogOption(
            child: makeText(statusName, statusColor),
            onPressed: () {
              Navigator.pop(context, status);
            },
          );
        }).toList(),
      );
    });
    newStatus.then((SolutionStatus? newStatusValue) {
      if (newStatusValue == null) {
        return;
      }
      log.info('picked change status to ${newStatusValue.name}');
      final service = ConnectionController.instance!.submissionsService;
      final request = _submission!.deepCopy();
      request.status = newStatusValue;
      service.updateSubmissionStatus(request).then(_updateSubmission);
    });
  }

  List<Widget> buildSubmissionCommonItems(BuildContext context) {
    if (_submission == null) {
      return [];
    }
    final leftColumn = <Widget>[];
    final theme = Theme.of(context);

    Padding wrapIntoPadding(Widget w, [double minHeight = 0]) {
      return Padding(
          child: Container(
            constraints: minHeight > 0 ? BoxConstraints(
              minHeight: minHeight,
            ) : null,
            child: w,
          ),
          padding: EdgeInsets.fromLTRB(0, 10, 0, 10)
      );
    }

    Text makeText(String text, [Color? color, bool underline = false]) {
      return Text(text,
          style: theme.textTheme.bodyText1!.merge(TextStyle(
            fontSize: 16,
            color: color,
            decoration: underline? TextDecoration.underline : null,
          ))
      );
    }

    void addText(String text, [Color? color]) {
      leftColumn.add(
        wrapIntoPadding(makeText(text, color))
      );
    }

    var status = _submission!.status;
    final finalStatuses = {SolutionStatus.PENDING_REVIEW, SolutionStatus.OK};
    bool hardDeadlinePassed = submissionHardDeadlinePassed();
    if (hardDeadlinePassed && finalStatuses.contains(status)) {
      status = SolutionStatus.HARD_DEADLINE_PASSED;
    }
    final gradingStatus = _submission!.gradingStatus;
    final graderName = _submission!.graderName;
    String statusName = statusMessageText(status, gradingStatus, graderName, false);
    Color? statusColor = statusMessageColor(context, status);
    if (gradingStatus != SubmissionGradingStatus.processed) {
      statusColor = null;
    }
    String dateSent = formatDateTime(_submission!.datetime.toInt());

    final whoCanRejudgeOrChangeStatus = [
      Role.ROLE_TEACHER_ASSISTANT, Role.ROLE_TEACHER, Role.ROLE_LECTURER,
    ];

    final rightColumn = <Widget>[];

    if (screen.loggedUser.defaultRole==Role.ROLE_ADMINISTRATOR || whoCanRejudgeOrChangeStatus.contains(screen.role)) {
      rightColumn.add(
        ElevatedButton(
          onPressed: _doRejudge,
          child: Container(
            width: 172,
            child: Text('Перетестировать', textAlign: TextAlign.center),
          ),
        )
      );
      final texts = {
        WhatToRejudge.thisSubmission: 'Только эту посылку',
        WhatToRejudge.brokenSubmissions: 'Неуспешные посылки задачи',
        WhatToRejudge.allSubmissions: 'Все посылки задачи',
      };
      rightColumn.add(
        DropdownButton(
          // icon: Icon(Icons.arrow_drop_down_circle_outlined),
          style: theme.textTheme.button,
          value: _whatToRejudge,
          // underline: Container(),
          onChanged: (WhatToRejudge? value) {
            if (value!=null) {
              setState((){
                _whatToRejudge = value;
                FocusManager.instance.primaryFocus?.unfocus();
              });
            }
          },
          items: texts.entries.map((e) {
            return DropdownMenuItem<WhatToRejudge>(
              value: e.key,
              child: Container(
                width: 180,
                child: Text(e.value, textAlign: TextAlign.center)
              ),
            );
          }).toList(),
        )
      );
    }
    bool canChangeStatus = screen.loggedUser.defaultRole==Role.ROLE_ADMINISTRATOR || whoCanRejudgeOrChangeStatus.contains(screen.role);
    final statusItems = <Widget>[
      makeText('Статус: '),
      makeText(statusName, statusColor),
    ];
    if (canChangeStatus && gradingStatus==SubmissionGradingStatus.processed) {
      statusItems.add(TextButton(onPressed: () {
        showChangeStatusDialog(context, status);
      }, child: makeText('Изменить', null, true)));
    }
    leftColumn.add(wrapIntoPadding(Row(children: statusItems), 28));
    
    addText('Отправлена: $dateSent');


    if (rightColumn.isEmpty) {
      return leftColumn;
    }
    else {
      return [Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(children: leftColumn, crossAxisAlignment: CrossAxisAlignment.start),
          Spacer(),
          Column(children: rightColumn, crossAxisAlignment: CrossAxisAlignment.end),
        ],
      )];
    }
  }

  List<Widget> buildDeadlineItems(BuildContext context) {
    Padding wrapIntoPadding(Widget w) {
      return Padding(
          child: w,
          padding: EdgeInsets.fromLTRB(0, 10, 0, 10)
      );
    }
    final theme = Theme.of(context);
    Text makeText(String text, [Color? color, bool underline = false]) {
      return Text(text,
          style: theme.textTheme.bodyText1!.merge(TextStyle(
            fontSize: 16,
            color: color,
            decoration: underline? TextDecoration.underline : null,
          ))
      );
    }
    List<Widget> result = [];
    int submitted = _submission!.datetime.toInt();
    int hardDeadline = _submission!.hardDeadline.toInt();
    int softDeadline = _submission!.softDeadline.toInt();
    bool hardDeadlinePassed = false;
    if (hardDeadline > 0) {
      hardDeadlinePassed = submitted > hardDeadline;
      if (hardDeadlinePassed) {
        String dateFormat = formatDateTime(hardDeadline);
        String message = 'Решение отправлено после жесткого дедлайна $dateFormat, оно не будет зачтено';
        result.add(wrapIntoPadding(makeText(message, Colors.red)));
      }
    }
    if (!hardDeadlinePassed && softDeadline > 0) {
      int secondsOverdue = submitted - softDeadline;
      int hoursOverdue = secondsOverdue ~/ 60 ~/ 60;
      int penalty = _problemMetadata!.deadlines.softDeadline * hoursOverdue;
      if (penalty > 0) {
        String dateFormat = formatDateTime(softDeadline);
        penalty = math.min(penalty, (_problemMetadata!.fullScoreMultiplier * 100).round());
        String scoreFormat = formatScoreInRussian(penalty);
        String message = 'Решение отправлено после дедлайна $dateFormat, штраф $scoreFormat';
        result.add(wrapIntoPadding(makeText(message, Colors.red)));
      }
    }
    return result;
  }

  bool submissionHardDeadlinePassed() {
    if (_submission == null) {
      return false;
    }
    int submitted = _submission!.datetime.toInt();
    int hardDeadline = _submission!.hardDeadline.toInt();
    bool hardDeadlinePassed = false;
    if (hardDeadline > 0) {
      hardDeadlinePassed = submitted > hardDeadline;
    }
    return hardDeadlinePassed;
  }

  List<Widget> buildLinkItems(BuildContext context) {
    Padding wrapIntoPadding(Widget w, [double topPadding = 10]) {
      return Padding(
          child: w,
          padding: EdgeInsets.fromLTRB(0, topPadding, 0, 10)
      );
    }
    final theme = Theme.of(context);
    Text makeText(String text, [Color? color, bool underline = false]) {
      return Text(text,
          style: theme.textTheme.bodyText1!.merge(TextStyle(
            fontSize: 16,
            color: color,
            decoration: underline? TextDecoration.underline : null,
          ))
      );
    }
    final currentRoute = ModalRoute.of(context)!.settings.name;
    final problemUrl = '$currentRoute/problem:${_submission!.problemId}';

    final problemLinkItem = wrapIntoPadding(Row(children: [
      makeText('Задача: '),
      TextButton(
        onPressed: () {
          Navigator.pushNamed(context, problemUrl).then((_) {
            _loadSubmission(true);
          });
        },
        child: makeText(_problemData!.title, null, true),
      )
    ]));

    void showDiff(Int64 submissionId) {
      final myself = 'submission:${_submission!.id}';
      final other = 'submission:$submissionId';
      final link = '/diffview/$myself...$other';
      Navigator.pushNamed(context, link);
    }

    void switchSubmission(Int64 submissionId) {
      Navigator.pushReplacement(context, PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
          settings: RouteSettings(name: '/submissions/${screen.courseUrlPrefix}/$submissionId'),
        pageBuilder: (context, _, __) {
          return SubmissionScreen(
            user: screen.loggedUser,
            courseUrlPrefix: screen.courseUrlPrefix,
            submissionId: submissionId,
            course: screen.course,
            role: screen.role,
            courseData: screen.courseData,
          );
        }
      ));
    }

    Widget? submissionHistoryItems;
    if (_submissionsHistory.length > 1) {
      final rowItems = <Widget>[
        Container(
          child: makeText('История решений задачи: '),
          padding: EdgeInsets.fromLTRB(0, 4, 0, 0),
        )
      ];
      for (final entry in _submissionsHistory) {
        String title = submissionListEntryToString(entry);
        if (rowItems.length > 1) {
          rowItems.add(makeText(', '));
        }
        bool isCurrent = entry.submissionId == _submission!.id;
        if (isCurrent) {
          rowItems.add(Container(
            child: makeText(title),
            padding: EdgeInsets.fromLTRB(0, 4, 0, 0),
          ));
        }
        else {
          rowItems.add(Container(child: TextButton(
            onPressed: () => switchSubmission(entry.submissionId),
            child: makeText(title, null, true)),
            padding: EdgeInsets.fromLTRB(0, 0, 0, 0),
          ));
          rowItems.add(Container(child: TextButton(
              onPressed: () => showDiff(entry.submissionId),
              child: makeText('[diff]', null, true)),
            padding: EdgeInsets.fromLTRB(0, 0, 0, 0),
          ));
        }
      }
      submissionHistoryItems = wrapIntoPadding(Wrap(children: rowItems), 6);
    }

    return submissionHistoryItems==null ? [problemLinkItem] : [
      problemLinkItem, submissionHistoryItems
    ];
  }

  void _doRejudge() {
    final service = ConnectionController.instance!.submissionsService;

    // make cleaned copies of request parameters to prevent
    // HTTP 413 error (Request Entity Too Large)
    final courseForRequest = Course(
      id: _course!.id,
      dataId: _course!.dataId
    );

    RejudgeRequest request;
    if (_whatToRejudge == WhatToRejudge.thisSubmission) {
      final submissionForRequest = Submission(
        id: _submission!.id,
        problemId: _problemData!.id,
      );
      request = RejudgeRequest(
        course: courseForRequest,
        problemId: _problemData!.id,
        submission: submissionForRequest,
      );
    }
    else if (_whatToRejudge == WhatToRejudge.brokenSubmissions) {
      request = RejudgeRequest(
        course: courseForRequest,
        problemId: _problemData!.id,
        onlyFailedSubmissions: true,
      );
    }
    else if (_whatToRejudge == WhatToRejudge.allSubmissions) {
      request = RejudgeRequest(
        course: courseForRequest,
        problemId: _problemData!.id,
        onlyFailedSubmissions: false,
      );
    }
    else {
      request = RejudgeRequest();
    }

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
          child: Text('${file.name}:', style: fileHeadStyle))
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
          contents.add(createFilePreview(context, file.name, fileContent, true, true));
        }
        else {
          contents.add(SizedBox(height: 20));
        }
      }

    }

    return contents;
  }

  static const signalDescriptions = {
    1: ['SIGHUP'],
    2: ['SIGINT'],
    3: ['SIGQUIT'],
    4: ['SIGILL'],
    5: ['SIGTRAP'],
    6: ['SIGABRT'],
    7: ['SIGBUS'],
    8: ['SIGFPE'],
    9: ['SIGKILL', 'возможно лимит ресурсов'],
    10: ['SIGUSR1'],
    11: ['SIGSEGV', 'ошибки работы с памятью'],
    12: ['SIGUSR2'],
    13: ['SIGPIPE', 'попытка записать в закрытый канал или сокет'],
    14: ['SIGALRM'],
    15: ['SIGTERM'],
    16: ['SIGSTKFLT'],
    17: ['SIGCHLD'],
    18: ['SIGCONT'],
    19: ['SIGSTOP'],
    20: ['SIGTSTP'],
    21: ['SIGTTIN'],
    22: ['SIGTTOU'],
    23: ['SIGURG'],
    24: ['SIGXCPU'],
    25: ['SIGXFSZ'],
    26: ['SIGVTALRM'],
    27: ['SIGPROF'],
    28: ['SIGWINCH'],
    29: ['SIGIO'],
    30: ['SIGPWR'],
    31: ['SIGSYS'],
  };

  static String runtimeErrorDescription(int signum) {
    String result = '';
    if (signalDescriptions.containsKey(signum)) {
      final description = signalDescriptions[signum]!;
      final sigName = description.first;
      final comment = description.length>1 ? description[1] : '';
      result = 'Процесс прибит сигналом $sigName';
      if (comment.isNotEmpty) {
        result += ' ($comment)';
      }
    }
    else {
      result = 'Процесс прибит сигналом с номером $signum';
    }
    return result;
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
    else if (_submission!.status == SolutionStatus.CHECK_FAILED) {
      contents.add(Container(
          padding: fileHeadPadding,
          child: Text('Лог тестирующий системы:', style: fileHeadStyle))
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
      String stdoutContent = brokenTestCase.stdout.trim();
      if (stdoutContent.isNotEmpty) stdoutContent = '=== stdout:\n$stdoutContent\n\n';
      String stderrContent = brokenTestCase.stderr.trim();
      if (stderrContent.isNotEmpty) stderrContent = '=== stderr:\n$stderrContent';
      String messageContent = stdoutContent + stderrContent;
      if (messageContent.isNotEmpty) {
        fileContent = messageContent;
      }
      brokenTestNumber = brokenTestCase.testNumber.toInt();
      contents.add(Container(
          padding: fileHeadPadding,
          child: Text('Ошибка выполнения на тесте $brokenTestNumber:', style: fileHeadStyle))
      );
      final signalNumber = brokenTestCase.signalKilled;
      if (signalNumber > 0) {
        final errorDescription = runtimeErrorDescription(signalNumber);
        contents.add(Container(
            padding: fileHeadPadding,
            child: Text(errorDescription))
        );
      }
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
        contents.add(createFilePreview(context, '', fileContent, false, false));
      }
      else {
        contents.add(Text('Вывод слишком большой, отображается только первые $maxFileSizeToShow символов'));
        contents.add(createFilePreview(context, '', fileContent.substring(0, maxFileSizeToShow), false, false));
      }
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

  bool canMakeReview() {
    final whoCanComment = {
      Role.ROLE_TEACHER_ASSISTANT, Role.ROLE_TEACHER, Role.ROLE_LECTURER,
    };
    final userCanComment = screen.loggedUser.defaultRole==Role.ROLE_ADMINISTRATOR || whoCanComment.contains(screen.role);
    return userCanComment;
  }

  bool canSaveReviewChanges() {
    if (!canMakeReview() || _reviewHistory==null) {
      return false;
    }
    CodeReview newReview = CodeReview(
      globalComment: _globalCommentController.text.trim(),
      lineComments: _lineCommentController.comments
    );
    CodeReview? currentReview = _reviewHistory!.findBySubmissionId(screen.submissionId);
    bool result;
    if (currentReview == null) {
      result = newReview.contentIsNotEmpty;
    }
    else {
      result = !newReview.contentEqualsTo(currentReview);
    }
    return result;
  }

  final statusesToAction = {
    SolutionStatus.PENDING_REVIEW,
    SolutionStatus.CODE_REVIEW_REJECTED,
    SolutionStatus.PLAGIARISM_DETECTED,
    SolutionStatus.SUMMON_FOR_DEFENCE,
  };

  @override
  List<ScreenSubmitAction> submitActions(BuildContext context) {
    if (_submission==null || !canMakeReview()) {
      return [];
    }
    bool hasUnsavedComments = _hasUnsavedChanges;
    List<ScreenSubmitAction> result = [];
    final status = _submission?.status ?? SolutionStatus.ANY_STATUS_OR_NULL;
    
    bool reviewableStatus =
        status == SolutionStatus.PENDING_REVIEW ||
        status == SolutionStatus.SUMMON_FOR_DEFENCE ||
        status == SolutionStatus.CODE_REVIEW_REJECTED
    ;
    
    bool hasComments = _globalCommentController.text.trim().isNotEmpty ||
        _lineCommentController.comments.isNotEmpty;

    if (reviewableStatus && !submissionHardDeadlinePassed()) {
      result.add(
        ScreenSubmitAction(
          title: status==SolutionStatus.SUMMON_FOR_DEFENCE ? 'Зачесть решение' : 'Одобрить решение',
          onAction: _acceptSolution,
          color: Colors.green,
        )
      );
    }

    if (hasUnsavedComments && result.isEmpty) {
      result.add(
        ScreenSubmitAction(
          title: 'Сохранить замечания',
          onAction: _saveReviewComments,
        )
      );
    }
    if (hasUnsavedComments && hasComments && reviewableStatus) {
      result.add(
          ScreenSubmitAction(
            title: status==SolutionStatus.CODE_REVIEW_REJECTED? 'Сохранить замечания' : 'На доработку',
            onAction: _rejectSolution,
            color: status==SolutionStatus.CODE_REVIEW_REJECTED? null : Colors.red,
          )
      );
    }
    return result;
  }

  void _acceptSolution() {
    SolutionStatus status;
    bool reviewPassed = {SolutionStatus.CODE_REVIEW_REJECTED, SolutionStatus.PENDING_REVIEW}.contains(_submission!.status);
    bool skipDefence = _course!.disableDefence || _problemMetadata!.skipSolutionDefence;
    if (!_problemMetadata!.skipSolutionDefence && reviewPassed && !skipDefence) {
      status = SolutionStatus.SUMMON_FOR_DEFENCE;
    }
    else {
      status = SolutionStatus.OK;
    }
    _applyCodeReview(status);
  }

  void _saveReviewComments() {
    _applyCodeReview(_submission!.status);
  }

  void _rejectSolution() {
    SolutionStatus status = _submission!.status;
    if (status != SolutionStatus.SUMMON_FOR_DEFENCE) {
      status = SolutionStatus.CODE_REVIEW_REJECTED;
    }
    _applyCodeReview(status);
  }

  void _applyCodeReview(SolutionStatus status) {
    final codeReview = currentStateCodeReview..newStatus = status;
    log.info('sending new review state: ${codeReview.debugInfo()}');
    final service = ConnectionController.instance!.codeReviewService;
    service.applyCodeReview(codeReview)
        .then((CodeReview approvedCodeReview) {
      setState(() {
        _submission!.status = approvedCodeReview.newStatus;
      });
      _loadCodeReviews();
    });
  }


  Widget createFilePreview(
      BuildContext context,
      String fileName,
      String data,
      bool withLineNumbers,
      bool editableComments,
      ) {
    return SourceViewWidget(
      text: data,
      fileName: fileName,
      withLineNumbers: withLineNumbers,
      lineCommentController: editableComments? _lineCommentController : null,
    );
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
    void addDivider() {
      contents.add(Divider(
        height: 40,
        thickness: 2,
        color: dividerColor,
      ));
    }

    contents.addAll(buildSubmissionCommonItems(context));
    contents.addAll(buildDeadlineItems(context));
    contents.addAll(buildLinkItems(context));

    bool commentsAreReadOnly = !canMakeReview();

    if (commentsAreReadOnly) {
      final commentItems = buildReviewerCommentItems(context);
      if (commentItems.isNotEmpty) {
        addDivider();
        contents.add(Container(
            padding: mainHeadPadding,
            child: Text('Недоработки решения', style: mainHeadStyle))
        );
        contents.addAll(commentItems);
      }
    }

    addDivider();
    contents.add(Container(
        padding: mainHeadPadding,
        child: Text('Файлы решения', style: mainHeadStyle))
    );
    contents.addAll(buildSubmissionFileItems(context));

    final submissionErrors = buildSubmissionErrors(context);
    if (submissionErrors.isNotEmpty) {
      addDivider();
      contents.addAll(submissionErrors);
    }

    if (canMakeReview()) {
      addDivider();
      contents.add(Container(
          padding: mainHeadPadding,
          child: Text('Комментарий к решению', style: mainHeadStyle))
      );
      final globalCommentEditor = TextField(
        controller: _globalCommentController,
        keyboardType: TextInputType.multiline,
        maxLines: null,
      );
      contents.add(globalCommentEditor);
    }

    contents.add(SizedBox(height: 50));

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

const statusesFull = {
  SolutionStatus.ANY_STATUS_OR_NULL: 'Любой статус',
  SolutionStatus.PENDING_REVIEW: 'Ожидает ревью',
  SolutionStatus.OK: 'Решение зачтено',
  SolutionStatus.PLAGIARISM_DETECTED: 'Подозрение на плагиат',
  SolutionStatus.CODE_REVIEW_REJECTED: 'Отправлено на доработку',
  SolutionStatus.SUMMON_FOR_DEFENCE: 'Требуется защита',
  SolutionStatus.DISQUALIFIED: 'Дисквалификация',
  SolutionStatus.COMPILATION_ERROR: 'Ошибка компиляции',
  SolutionStatus.STYLE_CHECK_ERROR: 'Ошибка форматирования',
  SolutionStatus.RUNTIME_ERROR: 'Ошибка выполнения',
  SolutionStatus.WRONG_ANSWER: 'Неправильный ответ',
  SolutionStatus.VALGRIND_ERRORS: 'Ошибки Valgrind',
  SolutionStatus.TIME_LIMIT: 'Лимит времени',
  SolutionStatus.CHECK_FAILED: 'Ошибка тестирования',
  SolutionStatus.HARD_DEADLINE_PASSED: 'Прошел дедлайн',
};

const statusesShort = {
  SolutionStatus.ANY_STATUS_OR_NULL: 'ANY',
  SolutionStatus.PENDING_REVIEW: 'PR',
  SolutionStatus.DISQUALIFIED: 'DISQ',
  SolutionStatus.COMPILATION_ERROR: 'CE',
  SolutionStatus.STYLE_CHECK_ERROR: 'STY',
  SolutionStatus.RUNTIME_ERROR: 'RE',
  SolutionStatus.WRONG_ANSWER: 'WA',
  SolutionStatus.VALGRIND_ERRORS: 'VLG',
  SolutionStatus.TIME_LIMIT: 'TL',
  SolutionStatus.PLAGIARISM_DETECTED: 'CHEAT?',
  SolutionStatus.CODE_REVIEW_REJECTED: 'REJ',
  SolutionStatus.SUMMON_FOR_DEFENCE: 'SM',
  SolutionStatus.CHECK_FAILED: 'CF',
  SolutionStatus.HARD_DEADLINE_PASSED: 'DL',
};

String statusMessageText(SolutionStatus status, SubmissionGradingStatus gradingStatus, String graderName, bool shortVariant) {
  String message = '';
  if (gradingStatus == SubmissionGradingStatus.queued) {
    return shortVariant? '...' : 'В очереди на тестирование';
  }
  if (gradingStatus == SubmissionGradingStatus.assigned) {
    message = 'Тестируется';
    if (graderName.isNotEmpty) {
      message += ' ($graderName)';
    }
    return shortVariant? '...' : message;
  }
  if (!shortVariant) {
    if (statusesFull.containsKey(status)) {
      message = statusesFull[status]!;
    }
    else {
      message = status.name;
    }
  }
  else {
    if (statusesShort.containsKey(status)) {
      message = statusesShort[status]!;
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
    SolutionStatus.SUMMON_FOR_DEFENCE,
  };
  const badStatuses = {
    SolutionStatus.CODE_REVIEW_REJECTED,
    SolutionStatus.WRONG_ANSWER,
    SolutionStatus.RUNTIME_ERROR,
    SolutionStatus.VALGRIND_ERRORS,
    SolutionStatus.TIME_LIMIT,
    SolutionStatus.COMPILATION_ERROR,
    SolutionStatus.STYLE_CHECK_ERROR,
    SolutionStatus.HARD_DEADLINE_PASSED,
    SolutionStatus.DISQUALIFIED,
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
