import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:grpc/grpc_connection_interface.dart';
import 'package:tuple/tuple.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:intl/intl.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:protobuf/protobuf.dart';
import '../controllers/connection_controller.dart';
import '../controllers/courses_controller.dart';
import 'screen_base.dart';
import 'screen_submission.dart';

class SubmissionsListScreen extends BaseScreen {

  final String courseUrlPrefix;
  final SubmissionListQuery? initialFilter;

  SubmissionsListScreen({
    required User loggedUser,
    required this.courseUrlPrefix,
    this.initialFilter,
  }) : super(loggedUser: loggedUser);

  @override
  State<StatefulWidget> createState() {
    return SubmissionsListScreenState(
      screen: this,
      query: initialFilter
    );
  }
}

const AboutNarrowWidthThereshold = 850;
const NarrowWidthThereshold = 685;


class SubmissionsListScreenState extends BaseScreenState {

  final SubmissionsListScreen screen;
  late SubmissionListQuery query;
  Course _course = Course();
  Role _role = Role.ROLE_ANY;
  CourseData _courseData = CourseData();
  List<Tuple2<String,String>> _courseProblems = [];
  final _nameEditController = TextEditingController();
  List<SubmissionListEntry> _submissionEntries = [];
  grpc.ResponseStream<SubmissionListEntry>? _statusStream;

  SubmissionsListScreenState({
    required this.screen,
    SubmissionListQuery? query,
  }) : super(title: 'Посылки') {
    if (query == null) {
      this.query = SubmissionListQuery(
        statusFilter: SolutionStatus.ANY_STATUS_OR_NULL,
      ).deepCopy();
    }
    else {
      this.query = query.deepCopy();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCourse();
    _subscribeToNotifications();
  }

  void _subscribeToNotifications() {
    if (!mounted) {
      return;
    }
    log.info('subscribing to list notifications');
    _statusStream?.cancel();
    final submissionsService = ConnectionController.instance!.submissionsService;
    _statusStream = submissionsService.subscribeToSubmissionListNotifications(query);
    _statusStream!.listen((event) {
      log.info('got submission update on ${event.submissionId}');
      _updateSubmissionInList(event);
    }, onError: (error) {
      if (!mounted) {
        return;
      }
      if (error is grpc.GrpcError && error.code == grpc.StatusCode.cancelled) {
        _statusStream?.cancel();
        _statusStream = null;
        return;
      }
      log.info('got error: $error');
      Timer(Duration(seconds: 2), _subscribeToNotifications);
    });
  }

  void _updateSubmissionInList(SubmissionListEntry event) {
    setState((){
      bool found = false;
      for (var entry in _submissionEntries) {
        if (entry.submissionId == event.submissionId) {
          entry.updateStatus(event.status);
          found = true;
          break;
        }
      }
      if (!found) {
        _submissionEntries.insert(0, event);
      }
    });
  }

  void _loadCourse() {
    if (_course.id == 0) {
      CoursesController.instance!
          .loadCourseByPrefix(screen.loggedUser, screen.courseUrlPrefix)
          .then((Tuple2<Course,Role> value) {
            void afterLoadCourse() {
              _course = value.item1;
              _role = value.item2;
              title = 'Посылки курса ${_course.name}';
            }
            if (mounted) {
              setState(afterLoadCourse);
            }
            else {
              afterLoadCourse();
            }
            _loadCourseData();
      });
    }
  }

  void _loadCourseData() {
    if (_courseData.id.isEmpty) {
      CoursesController.instance!
          .loadCourseData(_course.dataId)
          .then((CourseData value) {
            if (mounted) {
              setState(() {
                _courseData = value;
              });
            }
            else {
              _courseData = value;
            }
            _populateCourseProblems();
            _sendListQuery(query);
      });
    }
  }
  
  void _populateCourseProblems() {
    List<Tuple2<String,String>> problemIdsAndTitles = [Tuple2('', 'Все задачи')];
    for (final section in _courseData.sections) {
      for (final lesson in section.lessons) {
        for (final problem in lesson.problems) {
          problemIdsAndTitles.add(Tuple2(problem.id, '${problem.title} (${problem.id})'));
        }
      }
    }
    if (mounted) {
      setState(() {
        _courseProblems = problemIdsAndTitles;
      });
    }
    else {
      _courseProblems = problemIdsAndTitles;
    }
  }

  void _setFilterProblemId(String? problemId) {
    problemId ??= '';
    bool changed = problemId != query.problemIdFilter;
    setState(() {
      query.problemIdFilter = problemId!;
      FocusManager.instance.primaryFocus?.unfocus();
    });
    if (changed) {
      _sendListQuery(query);
    }
  }

  void _setFilterStatus(SolutionStatus? status) {
    status ??= SolutionStatus.ANY_STATUS_OR_NULL;
    bool changed = status != query.statusFilter;
    setState(() {
      query.statusFilter = status!;
      FocusManager.instance.primaryFocus?.unfocus();
    });
    if (changed) {
      _sendListQuery(query);
    }
  }

  void _setShowMineSubmissions(bool? value) {
    value ??= false;
    setState(() {
      query.showMineSubmissions = value!;
    });
    _sendListQuery(query);
  }

  void _processSearch(String? userName) {
    if (userName == null) {
      if (_nameEditController.text.trim().isNotEmpty) {
        userName = _nameEditController.text.trim();
      }
    }
    SubmissionListQuery newQuery = query.copyWith((s) {
      if (userName != null) {
        s.nameQuery = userName.trim();
      }
      s.submissionId = Int64(0);
    });
    int? submissionId = int.tryParse(newQuery.nameQuery);
    if (submissionId != null && submissionId > 0) {
      newQuery = newQuery.copyWith((s) {
        s.submissionId = Int64(submissionId);
        s.nameQuery = '';
      });
    }
    setState(() {
      query = newQuery;
    });
    _sendListQuery(newQuery);
  }

  void reload() {
    _sendListQuery(query);
  }

  void _sendListQuery(SubmissionListQuery query) {
    final submissionsService = ConnectionController.instance!.submissionsService;
    final futureList = submissionsService.getSubmissionList(query);
    futureList.then(_setSubmissionsList);
  }

  void _setSubmissionsList(SubmissionListResponse listResponse) {
    setState(() {
      _submissionEntries = listResponse.entries;
    });
    _subscribeToNotifications();
  }

  Widget _createProblemSearchField(BuildContext context) {
    List<DropdownMenuItem<String>> menuItems = [];
    final styleTheme = Theme.of(context);
    final textTheme = styleTheme.primaryTextTheme;
    for (int i=0; i<_courseProblems.length; ++i) {
      final problem = _courseProblems[i];
      final textColor = i==0? styleTheme.hintColor : Colors.black87;
      final itemText = Text(
        problem.item2,
        style: textTheme.labelLarge!.merge(TextStyle(color: textColor)),
      );
      final itemValue = problem.item1;
      menuItems.add(DropdownMenuItem<String>(child: itemText, value: itemValue));
    }
    String currentValue = query.problemIdFilter;
    if (!_courseProblems.contains(currentValue)) {
      currentValue = '';
    }
    return Container(
        height: 48,
        child: DropdownButtonFormField<String>(
          items: menuItems,
          value: query.problemIdFilter,
          onChanged: _setFilterProblemId,
        )
    );
  }

  Widget _createStatusSearchField(BuildContext context) {
    List<DropdownMenuItem<SolutionStatus>> menuItems = [];
    final styleTheme = Theme.of(context);
    final textTheme = styleTheme.primaryTextTheme;
    bool first = true;
    for (final entry in statusesFull.entries) {
      Color textColor;
      if (first) {
        textColor = styleTheme.hintColor;
        first = false;
      }
      else {
        textColor = Colors.black87;
      }
      final itemText = Text(
        entry.value,
        style: textTheme.labelLarge!.merge(TextStyle(color: textColor)),
      );
      menuItems.add(DropdownMenuItem<SolutionStatus>(
        child: itemText,
        value: entry.key,
      ));
    }
    return Container(
        width: 220,
        height: 48,
        child: DropdownButtonFormField<SolutionStatus>(
          items: menuItems,
          value: query.statusFilter,
          onChanged: _setFilterStatus,
        )
    );
  }

  Widget _createNameSearchField(BuildContext context) {
    final styleTheme = Theme.of(context);
    final textTheme = styleTheme.primaryTextTheme;
    return Expanded(
      child: TextField(
        style: textTheme.labelLarge!.merge(TextStyle(color: Colors.black87)),
        controller: _nameEditController,
        decoration: InputDecoration(labelText: 'ID посылки или Фамилия/Имя'),
        onSubmitted: (name) => _processSearch(name),
      )
    );
  }

  Widget _createSearchButton(BuildContext context) {
    return Container(
      child: ElevatedButton(
        child: Icon(Icons.search),
        onPressed: () => _processSearch(null),
      ),
      margin: EdgeInsets.fromLTRB(10, 0, 0, 0),
    );
  }

  Widget _createShowMineCheckbox(BuildContext context) {
    return Container(
      height: 48,
      child: Row(
        children: [
          Checkbox(value: query.showMineSubmissions, onChanged: _setShowMineSubmissions),
          Expanded(child: Text('Отображать в списке мои собственные посылки'))
        ],
      ),
    );
  }

  Widget _createSearchBoxWidget(BuildContext context) {
    final firstRow = <Widget>[
      _createStatusSearchField(context),
      _createNameSearchField(context),
      _createSearchButton(context),
    ];
    final secondRow = <Widget>[
      Expanded(child: _createProblemSearchField(context))
    ];
    final searchControls = <Widget>[
      Row(
        children: firstRow,
        crossAxisAlignment: CrossAxisAlignment.end,
      ),
      Row(
        children: secondRow,
        crossAxisAlignment: CrossAxisAlignment.end,
      ),
      _createShowMineCheckbox(context),
    ];
    return Card(
      shadowColor: Theme.of(context).shadowColor,
      elevation: 8,
      child: Container(
        padding: EdgeInsets.fromLTRB(8, 0, 8, 10),
        child: Column(
          children: searchControls,
        ),
      )
    );
  }

  void _navigateToSubmission(Int64 submissionId, String problemId) {
    final routeBuilder = PageRouteBuilder(
        settings: RouteSettings(name: '/submissions/${screen.courseUrlPrefix}/${submissionId}'),
        pageBuilder: (context, animation, secondaryAnimation) {
          return SubmissionScreen(
            courseUrlPrefix: _course.urlPrefix,
            submissionId: submissionId,
            user: screen.loggedUser,
            course: _course,
            role: _role,
            courseData: _courseData,
          );
        }
    );
    Navigator.push(context, routeBuilder).then((_) {reload();});
  }

  @protected
  Widget buildCentralWidget(BuildContext context) {

    final screenWidth = MediaQuery.of(context).size.width;
    final narrow = screenWidth < NarrowWidthThereshold;
    final aboutNarrow = screenWidth < AboutNarrowWidthThereshold;

    if (_courseData.id.isEmpty) {
      return Center(child: Text('Загрузка данных...'));
    }
    String formatDateTime(Int64 timestamp) {
      DateFormat formatter = DateFormat(aboutNarrow? 'MM/dd, HH:mm' : 'yyyy-MM-dd, HH:mm:ss');
      DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp.toInt() * 1000);
      return formatter.format(dateTime);
    }
    Widget searchBox = _createSearchBoxWidget(context);
    Widget resultsView;
    if (_submissionEntries.isEmpty) {
      resultsView = Center(child: Text('Нет посылок'));
    }
    else {
      List<TableRow> tableItems = [];
      for (final entry in _submissionEntries) {
        String id = '${entry.submissionId}';
        String dateTime = formatDateTime(entry.timestamp);
        String name = '${entry.sender.lastName} ${entry.sender.firstName}';
        if (!aboutNarrow) {
          name += ' ${entry.sender.midName.trim()}';
        }
        String problemId = entry.problemId;
        String status = statusMessageText(entry.status, '', narrow);
        Color statusTextColor = statusMessageColor(context, entry.status);
        TableCell makeClickableCellFromText(String text, [Color? color]) {
          TextStyle textStyle = Theme.of(context).textTheme.bodyText1!;
          if (narrow) {
            textStyle = textStyle.copyWith(fontSize: textStyle.fontSize! - 2);
          }
          if (color != null) {
            textStyle = textStyle.copyWith(color: color);
          }
          return TableCell(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  child: Container(
                    height: 32,
                    padding: EdgeInsets.fromLTRB(4, 2, 4, 2),
                    alignment: Alignment.centerLeft,
                    child: Text(text, style: textStyle),
                  ),
                  onTap: () => _navigateToSubmission(entry.submissionId, entry.problemId),
                ),
              )
          );
        }
        final tableRow = TableRow(
          children: [
            makeClickableCellFromText(id),
            makeClickableCellFromText(dateTime),
            makeClickableCellFromText(name),
            makeClickableCellFromText(problemId),
            makeClickableCellFromText(status, statusTextColor),
          ]
        );
        tableItems.add(tableRow);
      }
      BorderSide borderSide = BorderSide(
          color: Theme.of(context).colorScheme.secondary.withAlpha(50)
      );
      TableCell makeSimpleCellFromText(String text) {
        TextStyle textStyle = Theme.of(context).textTheme.bodyText1!.copyWith(fontWeight: FontWeight.bold);
        if (narrow) {
          textStyle = textStyle.copyWith(fontSize: textStyle.fontSize! - 2);
        }
        return TableCell(
            child: Container(
              height: 32,
              padding: EdgeInsets.fromLTRB(4, 2, 4, 2),
              alignment: Alignment.centerLeft,
              child: Text(text, style: textStyle),
            )
        );
      }
      final headerRow = TableRow(
        decoration: BoxDecoration(
          color: Theme.of(context).secondaryHeaderColor,
        ),
        children: [
          makeSimpleCellFromText('ID'),
          makeSimpleCellFromText('Время'),
          makeSimpleCellFromText(aboutNarrow? 'Фамилия Имя' : 'Фамилия Имя Отчество'),
          makeSimpleCellFromText('ID задачи'),
          makeSimpleCellFromText(narrow? 'Статус' : 'Статус выполнения'),
        ]
      );
      final table = Table(
        border: TableBorder(
          horizontalInside: borderSide,
          top: borderSide,
          bottom: borderSide,
          left: borderSide,
          right: borderSide
        ),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: {
          0: FixedColumnWidth(narrow? 35 : 50),
          1: FixedColumnWidth(narrow? 80 : (aboutNarrow? 100 : 180)),
          2: FlexColumnWidth(),
          3: FixedColumnWidth(narrow? 150 : 180),
          4: FixedColumnWidth(narrow? 50 : 180),
        },
        children: [headerRow] + tableItems,
      );
      double availableHeight = MediaQuery.of(context).size.height - 258;
      resultsView = Container(
        constraints: BoxConstraints(
          maxHeight: availableHeight
        ),
        child: SingleChildScrollView(
          child: table,
        ),
        padding: EdgeInsets.fromLTRB(8, 8, 8, 8),
      );
    }
    return Column(children: [ SizedBox(height: 8), searchBox, SizedBox(height: 8), resultsView ]);
  }
}