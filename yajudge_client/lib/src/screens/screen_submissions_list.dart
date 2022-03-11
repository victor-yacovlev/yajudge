import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:tuple/tuple.dart';
import 'package:yajudge_common/src/generated/yajudge.pb.dart';
import 'package:yajudge_common/yajudge_common.dart';

import '../controllers/connection_controller.dart';
import '../controllers/courses_controller.dart';
import 'screen_base.dart';
import 'screen_course_problem.dart';
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

class SubmissionsListScreenState extends BaseScreenState {

  final SubmissionsListScreen screen;
  late SubmissionListQuery query;
  Course _course = Course();
  Role _role = Role.ROLE_ANY;
  CourseData _courseData = CourseData();
  List<Tuple2<String,String>> _courseProblems = [];
  TextEditingController _nameEditController = TextEditingController();
  List<SubmissionListEntry> _submissionEntries = [];

  final statuses = <String,SolutionStatus>{
    'Любой статус': SolutionStatus.ANY_STATUS_OR_NULL,
    'Решение зачтено': SolutionStatus.OK,
    'Ожидает ревью': SolutionStatus.PENDING_REVIEW,
    'Защита': SolutionStatus.ACCEPTABLE,
    'Неправильный ответ': SolutionStatus.WRONG_ANSWER,
    'Ошибка выполнения': SolutionStatus.RUNTIME_ERROR,
    'Ошибки Valgrind': SolutionStatus.VALGRIND_ERRORS,
    'Ошибка компиляции': SolutionStatus.COMPILATION_ERROR,
    'Ошибка форматирования': SolutionStatus.STYLE_CHECK_ERROR,
    'Тестируется': SolutionStatus.GRADER_ASSIGNED,
    'Подозрение на плагиат': SolutionStatus.PLAGIARISM_DETECTED,
    'Отправлено на доработку': SolutionStatus.CODE_REVIEW_REJECTED,
    'Дисквалифицированы': SolutionStatus.DISQUALIFIED,
    'Неуспешная защита': SolutionStatus.DEFENCE_FAILED,
    'Новые посылки': SolutionStatus.SUBMITTED,
  };

  SubmissionsListScreenState({
    required this.screen,
    SubmissionListQuery? query,
  }) : super(title: 'Посылки') {
    if (query == null) {
      this.query = SubmissionListQuery(
        statusFilter: SolutionStatus.ANY_STATUS_OR_NULL,
      );
    }
    else {
      this.query = query;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCourse();
  }

  void _loadCourse() {
    if (_course.id == 0) {
      CoursesController.instance!
          .loadCourseByPrefix(screen.loggedUser, screen.courseUrlPrefix)
          .then((Tuple2<Course,Role> value) {
            final newFilter = query.copyWith((s) {
              s.courseId = _course.id;
            });
            final afterLoadCourse = () {
              _course = value.item1;
              _role = value.item2;
              title = 'Посылки курса ${_course.name}';
            };
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
            _sendListQuery();
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
    bool changed = problemId != query.problemIdFilter;
    setState(() {
      String id = '';
      if (problemId!=null) {
        id = problemId;
      }
      query = query.copyWith((s) {
        s.problemIdFilter = id;
      });
    });
    if (changed) {
      _sendListQuery();
    }
  }

  void _setFilterStatus(SolutionStatus? status) {
    bool changed = status != query.statusFilter;
    setState(() {
      if (status == null) {
        status = SolutionStatus.ANY_STATUS_OR_NULL;
      }
      query = query.copyWith((s) {
        s.statusFilter = status!;
      });
    });
    if (changed) {
      _sendListQuery();
    }
  }

  void _setShowMineSubmissions(bool? value) {
    bool changed = value != query.showMineSubmissions;
    setState(() {
      query = query.copyWith((s) { s.showMineSubmissions = value!; });
    });
    if (changed) {
      _sendListQuery();
    }
  }

  void _processSearch(String? userName) {
    if (userName != null) {
      setState(() {
        query = query.copyWith((s) {
          s.nameQuery = userName.trim();
        });
      });
    }
    _sendListQuery();
  }

  void _sendListQuery() {
    final submissionsService = ConnectionController.instance!.submissionsService;
    final futureList = submissionsService.getSubmissionList(query);
    futureList.then(_setSubmissionsList);
  }

  void _setSubmissionsList(SubmissionListResponse listResponse) {
    setState(() {
      _submissionEntries = listResponse.entries;
    });
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
    for (final entry in statuses.entries) {
      Color textColor;
      if (first) {
        textColor = styleTheme.hintColor;
        first = false;
      }
      else {
        textColor = Colors.black87;
      }
      final itemText = Text(
        entry.key,
        style: textTheme.labelLarge!.merge(TextStyle(color: textColor)),
      );
      menuItems.add(DropdownMenuItem<SolutionStatus>(
        child: itemText,
        value: entry.value,
      ));
    }
    return Container(
        width: 200,
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
    Navigator.push(context, routeBuilder);
  }

  @protected
  Widget buildCentralWidget(BuildContext context) {
    if (_courseData.id.isEmpty) {
      return Center(child: Text('Загрузка данных...'));
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
        String dateTime = formatDateTime(entry.timestamp.toInt());
        String name = '${entry.sender.lastName} ${entry.sender.firstName} ${entry.sender.midName}'.trim();
        String problemId = entry.problemId;
        String status = entry.status.toString();
        final makeClickableCellFromText = (String text) {
          return TableCell(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  child: Container(
                    height: 32,
                    padding: EdgeInsets.fromLTRB(4, 2, 4, 2),
                    alignment: Alignment.centerLeft,
                    child: Text(text),
                  ),
                  onTap: () => _navigateToSubmission(entry.submissionId, entry.problemId),
                ),
              )
          );
        };
        final tableRow = TableRow(
          children: [
            makeClickableCellFromText(id),
            makeClickableCellFromText(dateTime),
            makeClickableCellFromText(name),
            makeClickableCellFromText(problemId),
            makeClickableCellFromText(status),
          ]
        );
        tableItems.add(tableRow);
      }
      BorderSide borderSide = BorderSide(
          color: Theme.of(context).colorScheme.secondary.withAlpha(50)
      );
      final makeSimpleCellFromText = (String text) {
        return TableCell(
            child: Container(
              height: 32,
              padding: EdgeInsets.fromLTRB(4, 2, 4, 2),
              alignment: Alignment.centerLeft,
              child: Text(text),
            )
        );
      };
      final headerRow = TableRow(
        decoration: BoxDecoration(
          color: Theme.of(context).secondaryHeaderColor,
        ),
        children: [
          makeSimpleCellFromText('ID'),
          makeSimpleCellFromText('Время'),
          makeSimpleCellFromText('Фамилия Имя Отчество'),
          makeSimpleCellFromText('ID задачи'),
          makeSimpleCellFromText('Статус выполнения'),
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
          0: FixedColumnWidth(50),
          1: FixedColumnWidth(180),
          2: FlexColumnWidth(),
          3: FixedColumnWidth(150),
          4: FixedColumnWidth(150),
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