import 'package:flutter/material.dart';
import 'package:flutter_treeview/flutter_treeview.dart';
import 'package:yajudge_common/yajudge_common.dart';

typedef CourseSelectCallback = void Function(String selectedKey, double initialScrollOffset);

class CourseLessonsTree extends StatefulWidget {

  final String courseUrl;
  final CourseData courseData;
  final CourseStatus courseStatus;
  final String selectedKey;
  final CourseSelectCallback? callback;
  final double initialScrollOffset; 

  CourseLessonsTree(
      {
        required this.courseData,
        required this.courseUrl,
        required this.courseStatus,
        required this.selectedKey,
        this.initialScrollOffset = 0.0,
        this.callback,
        Key? key,
      }
  ) : super(key: key);


  @override
  State<StatefulWidget> createState() => CourseLessonsTreeState();
}

class CourseLessonsTreeState extends State<CourseLessonsTree> {

  late TreeViewController treeViewController;
  late ScrollController scrollController;

  CourseLessonsTreeState() : super();

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController(initialScrollOffset: widget.initialScrollOffset);
    _createTreeViewController(widget.selectedKey, widget.courseStatus);
  }

  @override
  Widget build(BuildContext context) {
    TreeViewTheme theme;
    theme = _createTreeViewTheme(context);

    TreeView treeView = TreeView(
      primary: false,
      shrinkWrap: true,
      controller: treeViewController,
      theme: theme,
      onNodeTap: _navigationNodeSelected,
    );
    Container container = Container(
      padding: EdgeInsets.fromLTRB(0, 8, 0, 0),
      width: 300,
      constraints: BoxConstraints(
        minHeight: 200,
      ),
      child: treeView,
    );

    SingleChildScrollView scrollView = SingleChildScrollView(
      controller: scrollController,
      scrollDirection: Axis.vertical,
      child: container,
    );
    return scrollView;
  }

  void _createTreeViewController(String selectedKey, CourseStatus courseStatus) {
    if (selectedKey.isEmpty) {
      selectedKey = '#';
    }
    final items = _buildTreeViewControllerItems(selectedKey, courseStatus);
    treeViewController = TreeViewController(children: items, selectedKey: selectedKey);
  }

  List<Node> _buildTreeViewControllerItems(String selectedKey, CourseStatus courseStatus) {
    List<Node> firstLevelNodes = [];
    int firstLevelNumber = 1;
    firstLevelNodes.add(Node(
      key: '#',
      label: 'О курсе',
      icon: Icons.info_outlined,
    ));
    for (Section section in widget.courseData.sections) {
      String sectionKey = '/' + section.id;
      late List<Node> listToAddLessons;
      SectionStatus sectionStatus;
      int sectionIndex = widget.courseData.sections.indexOf(section);
      sectionStatus = courseStatus.sections[sectionIndex];
      if (section.name.isNotEmpty) {
        List<Node> secondLevelNodes = List.empty(growable: true);
        listToAddLessons = secondLevelNodes;
        int sectionNumber = firstLevelNumber;
        bool expanded = false;
        if (firstLevelNumber == 1) {
          expanded = true;
        }
        else if (selectedKey.isNotEmpty) {
          expanded = selectedKey.startsWith(sectionKey);
        }
        firstLevelNumber ++;
        String sectionPrefix = 'Часть ' + sectionNumber.toString();
        String sectionTitle = sectionPrefix + ':\n' + section.name;
        IconData? sectionIcon;

        if (sectionStatus.completed) {
          sectionIcon = Icons.done;
        }
        int scoreGot = sectionStatus.scoreGot.toInt();
        int scoreMax = sectionStatus.scoreMax.toInt();
        sectionTitle += ' ($scoreGot/$scoreMax)';

        Node sectionNode = Node(
          label: sectionTitle,
          key: sectionKey,
          children: secondLevelNodes,
          expanded: expanded,
          icon: sectionIcon,
        );
        firstLevelNodes.add(sectionNode);
      } else {
        listToAddLessons = firstLevelNodes;
      }
      for (Lesson lesson in section.lessons) {
        int lessonIndex = section.lessons.indexOf(lesson);
        final lessonStatus = sectionStatus.lessons[lessonIndex];

        final String lessonKey = sectionKey + '/' + lesson.id;
        IconData? lessonIcon;
        Color? lessonIconColor;
        String lessonTitle = lesson.name;

        if (lessonStatus.completed) {
          lessonIcon = Icons.check;
        }
        else if (!lessonStatus.blockedByPrevious && lessonStatus.blocksNext) {
          lessonIcon = Icons.arrow_forward_sharp;
        }
        else {
          lessonIcon = Icons.circle_outlined;
          lessonIconColor = Colors.transparent;
        }
        int scoreGot = lessonStatus.scoreGot.toInt();
        int scoreMax = lessonStatus.scoreMax.toInt();
        lessonTitle += ' ($scoreGot/$scoreMax)';

        Node lessonNode = Node(
          label: lessonTitle,
          key: lessonKey,
          icon: lessonIcon,
          iconColor: lessonIconColor,
          selectedIconColor: lessonIconColor,
        );
        listToAddLessons.add(lessonNode);
      }
    }
    return firstLevelNodes;
  }

  void _selectNavItem(String key) {
    setState(() {
      treeViewController =
          treeViewController.copyWith(selectedKey: key).withExpandToNode(key);
    });
  }

  void _navigationNodeSelected(String key) {
    if (key == widget.selectedKey) {
      return;
    }
    _selectNavItem(key);
    double initialSrollOffset = scrollController.offset;
    if (widget.callback != null) {
      widget.callback!(key, initialSrollOffset);
    }
  }

  TreeViewTheme _createTreeViewTheme(BuildContext context) {
    TreeViewTheme theme = TreeViewTheme(
      expanderTheme: ExpanderThemeData(
        type: ExpanderType.caret,
        modifier: ExpanderModifier.none,
        position: ExpanderPosition.start,
        size: 20,
      ),
      labelStyle: TextStyle(
        fontSize: 16,
        letterSpacing: 0.3,
      ),
      parentLabelStyle: TextStyle(
        fontSize: 16,
        letterSpacing: 0.1,
      ),
      iconTheme: IconThemeData(
        size: 18,
        color: Colors.grey.shade800,
      ),
      colorScheme: Theme.of(context).colorScheme,
    );
    return theme;
  }

}
