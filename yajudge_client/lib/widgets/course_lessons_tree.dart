import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_treeview/flutter_treeview.dart';
import 'package:yajudge_client/utils/utils.dart';
import 'package:yajudge_client/wsapi/courses.dart';

typedef CourseSelectCallback = void Function(String sectionKey, String lessonKey);

class CourseLessonsTree extends StatefulWidget {
  final String? sectionKey;
  final String? lessonKey;
  final String courseUrl;
  final CourseData courseData;
  final CourseSelectCallback? callback;

  CourseLessonsTree(
      this.courseData,
      this.courseUrl,
      {
        this.sectionKey,
        this.lessonKey,
        this.callback,
        Key? key,
      }
  ) : super(key: key);

  static Map<String,CourseLessonsTreeState> lastStates = Map();

  @override
  State<StatefulWidget> createState() {
    CourseLessonsTreeState? lastState;
    if (lastStates.containsKey(courseUrl)) {
      lastState = lastStates[courseUrl];
    }
    CourseLessonsTreeState state = CourseLessonsTreeState(prevState: lastState);
    lastStates[courseUrl] = state;
    return state;
  }
}

class CourseLessonsTreeState extends State<CourseLessonsTree> {

  CourseLessonsTreeState? prevState;

  TreeViewController? treeViewController;
  ScrollController? scrollController;

  double savedScrollPosition = 0.0;
  void saveScrollPosition() {
    if (scrollController != null) {
      savedScrollPosition = scrollController!.offset;
    }
  }

  CourseLessonsTreeState({this.prevState});

  @override
  Widget build(BuildContext context) {
    if (treeViewController == null) {
      return Text('Загрузка...');
    }
    TreeViewTheme theme;
    theme = _createTreeViewTheme(context);
    assert (treeViewController != null);
    TreeView treeView = TreeView(
      primary: false,
      shrinkWrap: true,
      controller: treeViewController!,
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
    scrollController = ScrollController(
      initialScrollOffset: prevState==null? 0.0 : prevState!.savedScrollPosition
    );
    SingleChildScrollView scrollView = SingleChildScrollView(
      controller: scrollController,
      scrollDirection: Axis.vertical,
      child: container,
    );
    return scrollView;
  }

  String? _selectedKey;

  String? _createTreeViewController(String? selectedKey) {
    List<Node> firstLevelNodes = List.empty(growable: true);
    int firstLevelNumber = 1;
    for (Section section in widget.courseData.sections) {
      String sectionKey = '/' + section.id;
      late List<Node> listToAddLessons;
      if (section.name.isNotEmpty) {
        List<Node> secondLevelNodes = List.empty(growable: true);
        listToAddLessons = secondLevelNodes;
        int sectionNumber = firstLevelNumber;
        late bool expanded;
        if (selectedKey == null && firstLevelNumber == 1) {
          expanded = true;
        } else if (selectedKey != null) {
          expanded = selectedKey.startsWith(sectionKey);
        }
        firstLevelNumber ++;
        String sectionPrefix = 'Часть ' + sectionNumber.toString();
        String sectionTitle = sectionPrefix + ':\n' + section.name;
        Node sectionNode = Node(
          label: sectionTitle,
          key: sectionKey,
          children: secondLevelNodes,
          expanded: expanded,
        );
        firstLevelNodes.add(sectionNode);
      } else {
        listToAddLessons = firstLevelNodes;
      }
      for (Lesson lesson in section.lessons) {
        final String lessonKey = sectionKey + '/' + lesson.id;
        if (selectedKey == null) {
          selectedKey = lessonKey;
        }
        Node lessonNode = Node(
          label: lesson.name,
          key: lessonKey,
        );
        listToAddLessons.add(lessonNode);
      }
    }
    treeViewController = TreeViewController(
      children: firstLevelNodes,
      selectedKey: selectedKey,
    );
    return selectedKey;
  }

  @override
  void initState() {
    super.initState();
    String? selectedKey;
    if (widget.sectionKey != null && widget.lessonKey != null) {
      selectedKey = '/' + widget.sectionKey! + '/' + widget.lessonKey!;
    }
    if (prevState != null && prevState!.treeViewController != null) {
      selectedKey = prevState!.treeViewController!.selectedKey;
      treeViewController = prevState!.treeViewController!.copyWith(
        selectedKey: selectedKey
      );
      for (Node node in prevState!.treeViewController!.children) {
        if (node.expanded) {
          treeViewController = treeViewController!.withExpandToNode(node.key);
        }
      }
    }
    if (selectedKey == null) {
      selectedKey = PlatformsUtils.getInstance().loadSettingsValue(
        'selected_lesson/' + widget.courseUrl
      );
    }
    if (treeViewController != null) {
      if (selectedKey != null) {
        treeViewController = treeViewController!.copyWith(selectedKey: selectedKey);
      }
    }
    else {
      selectedKey = _createTreeViewController(selectedKey);
    }
    if (prevState == null) {
      // first load of tree view:  navigate explicitly to selected item
      Future.delayed(Duration(milliseconds: 100), () {
        setState(() {
          _navigationNodeSelected(selectedKey!);
        });
      });
    } else {
      _selectedKey = _selectedKey;
    }
  }

  void _selectNavItem(String key) {
    setState(() {
      treeViewController =
          treeViewController!.copyWith(selectedKey: key).withExpandToNode(key);
    });
  }

  void _navigationNodeSelected(String key) {
    if (key == _selectedKey) {
      return;
    }
    _selectedKey = key;
    PlatformsUtils.getInstance().saveSettingsValue(
      'selected_lesson/' + widget.courseData.id,
      key,
    );
    _selectNavItem(key);
    List<String> parts = key.substring(1).split('/');
    assert (parts.length == 2);
    saveScrollPosition();
    if (widget.callback != null) {
      widget.callback!(parts[0], parts[1]);
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
