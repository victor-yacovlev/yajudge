import 'package:flutter/material.dart';
import 'package:tuple/tuple.dart';
import 'package:yajudge_common/yajudge_common.dart';
import '../controllers/connection_controller.dart';
import '../controllers/course_content_controller.dart';
import 'screen_base.dart';

class CourseProgressScreen extends BaseScreen {

  final String courseUrlPrefix;
  final CourseProgressRequest? initialFilter;

  CourseProgressScreen({
    required User loggedUser,
    required this.courseUrlPrefix,
    this.initialFilter,
  }) : super(loggedUser: loggedUser);

  @override
  State<StatefulWidget> createState() {
    return CourseProgressScreenState(
      screen: this,
      query: initialFilter
    );
  }
}

const AboutNarrowWidthThereshold = 850;
const NarrowWidthThereshold = 685;


class CourseProgressScreenState extends BaseScreenState {

  final CourseProgressScreen screen;
  late CourseProgressRequest query;
  CourseProgressResponse? _courseProgress;

  TextEditingController _nameFilterController = TextEditingController();

  CourseProgressScreenState({
    required this.screen,
    CourseProgressRequest? query,
  }) : super(title: 'Прогресс курса') {
    if (query == null) {
      this.query = CourseProgressRequest();
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
    if (query.course.id == 0 || query.course.dataId.isEmpty) {
      CourseContentController.instance!
          .loadCourseByPrefix(screen.loggedUser, screen.courseUrlPrefix)
          .then((Tuple2<Course,Role> value) {
            final newFilter = query.copyWith((s) {
              s.course = value.item1;
            });
            final afterLoadCourse = () {
              query = newFilter;
              title = 'Прогресс курса ${query.course.name}';
            };
            if (mounted) {
              setState(afterLoadCourse);
            }
            _loadCourseProgress();
      });
    }
  }
  
  void _loadCourseProgress() {
    final service = ConnectionController.instance!.progressService;
    final futureProgress = service.getProgress(query);
    futureProgress.then(_setCourseProgress).onError((error, _) {
      setState(() {
        errorMessage = error;
      });
    });
  }

  void _setCourseProgress(CourseProgressResponse response) {
    if (mounted) {
      setState(() {
        _courseProgress = response;
      });
    }
  }

  void _setIncludeProblemDetails(bool? value) {
    bool changed = value != query.includeProblemDetails;
    final newQuery = query.copyWith((s) { s.includeProblemDetails = value!; });
    setState(() {
      query = newQuery;
    });
    if (changed) {
      _sendProgressQuery(newQuery);
    }
  }

  void _processSearch(String? nameFilter) {
    if (nameFilter == null) {
      if (_nameFilterController.text.trim().isNotEmpty) {
        nameFilter = _nameFilterController.text.trim();
      }
    }
    CourseProgressRequest newQuery = query.copyWith((s) {
      if (nameFilter != null) {
        s.nameFilter = nameFilter.trim();
      }
    });
    setState(() {
      query = newQuery;
    });
    _sendProgressQuery(newQuery);
  }

  void _sendProgressQuery(CourseProgressRequest query) {
    final service = ConnectionController.instance!.progressService;
    final futureResponse = service.getProgress(query);
    futureResponse.then(_setSubmissionsList);
  }

  void _setSubmissionsList(CourseProgressResponse progressResponse) {
    setState(() {
      _courseProgress = progressResponse;
    });
  }

  Widget _createNameSearchField(BuildContext context) {
    final styleTheme = Theme.of(context);
    final textTheme = styleTheme.primaryTextTheme;
    return Expanded(
      child: TextField(
        style: textTheme.labelLarge!.merge(TextStyle(color: Colors.black87)),
        controller: _nameFilterController,
        decoration: InputDecoration(labelText: 'Фамилия/Имя или группа'),
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

  Widget _createIncludeProblemDetailsCheckbox(BuildContext context) {
    return Container(
      height: 48,
      child: Row(
        children: [
          Checkbox(value: query.includeProblemDetails, onChanged: _setIncludeProblemDetails),
          Expanded(child: Text('Отображать подробности о задачах'))
        ],
      ),
    );
  }

  Widget _createSearchBoxWidget(BuildContext context) {
    final firstRow = <Widget>[
      _createNameSearchField(context),
      _createSearchButton(context),
    ];
    final searchControls = <Widget>[
      Row(
        children: firstRow,
        crossAxisAlignment: CrossAxisAlignment.end,
      ),
      _createIncludeProblemDetailsCheckbox(context),
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

  List<Widget> _buildProgressTables(BuildContext context) {
    List<Widget> result = [];
    if (_courseProgress!.entries.isEmpty) {
      result.add(Text('Нет студентов'));
      return result;
    }
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    TextStyle tableDataStyle = textTheme.bodyText1!;
    TextStyle tableHeadingStyle = tableDataStyle.copyWith(fontWeight: FontWeight.bold);
    TextStyle tableLightStyle = tableDataStyle.copyWith(color: tableDataStyle.color!.withAlpha(50));
    String currentGroupName = '';
    List<TableRow> currentGroupTableRows = [];
    List<TableRow> currentGroupProblemsTableRows = [];
    bool justStarted = true;
    List<TableCell> tableHeadingCells = [];
    List<TableCell> problemHeadingCells = [];
    double progressColumnWidth = 140;
    if (!query.includeProblemDetails) {
      progressColumnWidth = MediaQuery.of(context).size.width - 32 - 280 - 100;
    }
    final columnWidths = {
      0: FixedColumnWidth(280),
      1: FixedColumnWidth(100),
      2: FixedColumnWidth(progressColumnWidth),
    };
    Map<int,TableColumnWidth> problemColumnWidths = {};
    if (query.includeProblemDetails) {
      for (int i=0; i<_courseProgress!.problems.length; i++) {
        if (i < _courseProgress!.problems.length-1) {
          problemColumnWidths[i] = FixedColumnWidth(24);
        }
        else {
          double screenWidth = MediaQuery.of(context).size.width - 32;
          double widthsUsed = 0;
          for (final columnWidth in columnWidths.values) {
            if (columnWidth is FixedColumnWidth) {
              widthsUsed += columnWidth.value;
            }
          }
          problemColumnWidths[i] = FixedColumnWidth(screenWidth-widthsUsed);
        }
      }
    }
    final textToCell = (String text, [TextStyle? style, double? height]) {
      if (style == null) {
        style = tableDataStyle;
      }
      if (height == null) {
        height = 32;
      }
      return TableCell(
        child: Container(
          child: Text(text, style: style),
          height: height,
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.fromLTRB(4, 0, 4, 0),
        )
      );
    };
    double headingHeight = query.includeProblemDetails? 130 : 32;
    tableHeadingCells.add(textToCell('Студент', tableHeadingStyle, headingHeight));
    tableHeadingCells.add(textToCell('Курс пройден', tableHeadingStyle, headingHeight));
    tableHeadingCells.add(textToCell('Результат', tableHeadingStyle, headingHeight));
    if (query.includeProblemDetails) {
      for (final problem in _courseProgress!.problems) {
        final problemId = problem.id;
        TextStyle smallStyle = tableHeadingStyle.copyWith(fontSize: tableHeadingStyle.fontSize!-3);
        final text = Text(problemId, style: smallStyle);
        final rotatedBox = RotatedBox(quarterTurns: 3, child: text);
        final container = Container(
          child: rotatedBox,
          width: 16,
          height: headingHeight,
          alignment: Alignment.bottomLeft,
          padding: EdgeInsets.fromLTRB(4, 0, 4, 4),
        );
        final cell = TableCell(child: container);
        problemHeadingCells.add(cell);
      }
    }
    final addTableForGroup = () {
      final groupHeadingStyle = textTheme.headline5!;
      final groupText = currentGroupName.isEmpty
          ? 'Студенты без группы' : 'Группа $currentGroupName';
      result.add(
          Container(
            padding: EdgeInsets.fromLTRB(0, 16, 0, 16),
            alignment: Alignment.centerLeft,
            child: Text(groupText, style: groupHeadingStyle),
          )
      );
      final borderSide = BorderSide(
          color: Theme.of(context).colorScheme.secondary.withAlpha(50)
      );
      List<Widget> tablesRowItems = [];
      final mainTable = Table(
        children: [
          TableRow(
            children: tableHeadingCells,
            decoration: BoxDecoration(color: Theme.of(context).secondaryHeaderColor),
          )
        ] + currentGroupTableRows,
        border: TableBorder(
            horizontalInside: borderSide,
            top: borderSide,
            bottom: borderSide,
            left: borderSide,
            right: borderSide
        ),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: columnWidths,
      );
      tablesRowItems.add(mainTable);
      if (query.includeProblemDetails) {
        final problemsTable = Table(
          children: [
            TableRow(
              children: problemHeadingCells,
              decoration: BoxDecoration(color: Theme.of(context).secondaryHeaderColor),
            )
          ] + currentGroupProblemsTableRows,
          border: TableBorder(
              horizontalInside: borderSide,
              top: borderSide,
              bottom: borderSide,
              left: BorderSide.none,
              right: borderSide
          ),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: problemColumnWidths,
        );
        double problemsTableWidth = 24 * _courseProgress!.problems.length + 2;
        double mainTableWidth = 2 + 280 + 100 + 140;
        double spaceForProblemsTable = MediaQuery.of(context).size.width - 30 - mainTableWidth;
        final scrollView = SingleChildScrollView(
          child: Container(
            child: problemsTable,
            width: problemsTableWidth,
          ),
          scrollDirection: Axis.horizontal,
        );

        tablesRowItems.add(
          Container(
            child: scrollView,
            width: spaceForProblemsTable,
          )
        );
      }
      result.add(Row(children: tablesRowItems));
      currentGroupProblemsTableRows = [];
      currentGroupTableRows = [];
    };
    for (final entry in _courseProgress!.entries) {
      if (!justStarted && entry.user.groupName!=currentGroupName) {
        addTableForGroup();
        currentGroupName = entry.user.groupName;
      }
      justStarted = false;
      currentGroupName = entry.user.groupName;
      List<TableCell> mainRowCells = [];
      List<TableCell> problemTableRowCells = [];
      String fullName = entry.user.lastName + ' ' + entry.user.firstName;
      if (entry.user.midName.isNotEmpty) {
        fullName += ' ' + entry.user.midName;
      }
      mainRowCells.add(textToCell(fullName));
      final iconColor = tableDataStyle.color!.withAlpha(90);
      Icon courseCompleted = entry.courseCompleted
        ? Icon(Icons.check, color: iconColor) : Icon(Icons.clear, color: iconColor);
      mainRowCells.add(TableCell(
        child: Container(
          alignment: Alignment.center,
          child: courseCompleted,
        )
      ));
      double scoreGot = entry.scoreGot;
      double scoreMax = entry.scoreMax;
      int rate = (100 * scoreGot/scoreMax).round();
      String progressInfo = '$rate%';
      String progressInfoDetails  = ' ($scoreGot/$scoreMax)';
      mainRowCells.add(TableCell(
        child: Container(
          child: Row(
            children: [
              Text(progressInfo, style: tableDataStyle),
              Text(progressInfoDetails, style: tableLightStyle),
            ],
          ),
          height: 32,
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.fromLTRB(4, 0, 4, 0),
        ),
      ));
      if (query.includeProblemDetails) {
        for (final status in entry.statuses) {
          bool ok = status.completed;
          bool wrong = !status.completed && status.submitted > 0;
          Widget w; 
          if (ok) {
            w = Icon(Icons.check, color: iconColor, size: 16);
          }
          else if (wrong) {
            w = Icon(Icons.error_outline_sharp, color: iconColor, size: 16);
          }
          else {
            w = Icon(Icons.clear, color: Colors.transparent, size: 16);
          }
          final iconContainer = Container(
            child: w,
            width: 16,
            height: 32,
            alignment: Alignment.center,
          );
          problemTableRowCells.add(TableCell(child: iconContainer));
        }
      }
      currentGroupTableRows.add(TableRow(children: mainRowCells));
      currentGroupProblemsTableRows.add(TableRow(children: problemTableRowCells));
    }
    if (currentGroupTableRows.isNotEmpty) {
      addTableForGroup();
    }
    return result;
  }

  @protected
  Widget buildCentralWidget(BuildContext context) {

    final screenWidth = MediaQuery.of(context).size.width;
    final narrow = screenWidth < NarrowWidthThereshold;
    final aboutNarrow = screenWidth < AboutNarrowWidthThereshold;

    Widget searchBox = _createSearchBoxWidget(context);
    Widget resultsView;
    if (_courseProgress == null) {
      resultsView = Text('');
    }
    else {
      double availableHeight = MediaQuery.of(context).size.height - 258;
      final progressTables = _buildProgressTables(context);
      resultsView = Container(
        constraints: BoxConstraints(
          maxHeight: availableHeight
        ),
        child: SingleChildScrollView(
          child: Column(children: progressTables),
        ),
        padding: EdgeInsets.fromLTRB(8, 8, 8, 8),
      );
    }
    return Column(children: [ SizedBox(height: 8), searchBox, SizedBox(height: 8), resultsView ]);
  }
}