import 'dart:math';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import '../controllers/connection_controller.dart';
import '../widgets/expandable_fab.dart';
import 'package:yajudge_common/yajudge_common.dart';

abstract class BaseScreen extends StatefulWidget {
  final User loggedUser;
  final bool allowUnauthorized;
  final String secondLevelTabId;

  BaseScreen({
    required this.loggedUser,
    this.allowUnauthorized=false,
    this.secondLevelTabId='',
    Key? key
  }) : super(key: key) ;
}

class ScreenSubmitAction {
  final String title;
  final Function()? onAction;
  final Color? color;

  ScreenSubmitAction({
    required this.title,
    this.onAction,
    this.color,
  });
}

class ScreenAction {
  final Icon icon;
  final String title;
  final Function() onAction;

  ScreenAction({
    required this.icon,
    required this.title,
    required this.onAction,
  });

}

class ScreenActions {
  final Icon rootIcon;
  final String rootTitle;
  final bool isPrimaryActions;
  final Function()? onRootAction;
  final List<ScreenAction> actions;

  ScreenAction? get rootAction {
    if (onRootAction!=null && actions.length==0) {
      return ScreenAction(icon: rootIcon, title: rootTitle, onAction: onRootAction!);
    } else {
      return null;
    }
  }

  ScreenActions({
    required this.rootIcon,
    required this.rootTitle,
    bool? isPrimary,
    Function()? onRoot,
    List<ScreenAction>? actions,
  })
      : isPrimaryActions = isPrimary!=null? isPrimary : true,
        onRootAction = onRoot,
        this.actions = actions!=null? actions : List.empty() ;
}

class SecondLevelNavigationTab {
  final String id;
  final String title;
  final Icon icon;
  final Widget Function(BuildContext context) builder;

  SecondLevelNavigationTab(this.id, this.title, this.icon, this.builder);
}

abstract class BaseScreenState extends State<BaseScreen> with SingleTickerProviderStateMixin {
  String title;
  final log = Logger('BaseScreenState');

  final secondLevelNavigationKey = GlobalKey<NavigatorState>();

  final double leftNavigationWidthThreshold = 750;
  final double shortProfileNameWidthThreshold = 750;
  final double leftNavigationPadding = 320;

  TabController? _secondLevelTabController;

  BaseScreenState({required this.title}) : super();

  @override
  void initState() {
    super.initState();
    final tabs = secondLevelNavigationTabs();
    if (tabs.isNotEmpty) {
      _secondLevelTabController = TabController(
          length: tabs.length,
          vsync: this,
      );
    }
    // WidgetsBinding.instance!.addPostFrameCallback((timeStamp) {
    //   if (widget.loggedUser.id==0 && !widget.allowUnauthorized) {
    //       setState(() {
    //         Navigator.pushReplacementNamed(context, '/login');
    //       }
    //     );
    //   }
    // });
  }

  @override
  void dispose() {
    if (_secondLevelTabController != null) {
      _secondLevelTabController!.dispose();
    }
    super.dispose();
  }


  String _userProfileName(BuildContext context) {
    if (widget.loggedUser.id == 0) {
      return '';
    }
    String visibleName;
    double screenWidth = MediaQuery.of(context).size.width;
    User user = widget.loggedUser;
    if (user.firstName.isNotEmpty && user.lastName.isNotEmpty)
    {
      if (screenWidth < shortProfileNameWidthThreshold) {
        visibleName = user.firstName[0] + user.lastName[0];
      } else {
        visibleName = user.firstName + ' ' + user.lastName;
      }
    } else {
      if (screenWidth < shortProfileNameWidthThreshold) {
        visibleName = user.id.toString();
      } else {
        visibleName = 'ID (' + user.id.toString() + ')';
      }
    }
    return visibleName;
  }


  void _doLogout() {
    ConnectionController.instance!.sessionCookie = '';
    setState(() {
      Navigator.pushReplacementNamed(context, '/login');
    });
  }

  void _goToProfile() {
    Navigator.pushNamed(context, '/users/myself');
  }

  Widget? _buildUserProfileWidget(BuildContext context) {
    if (widget.loggedUser.id==0) {
      return null;
    }
    Color profileColor = Colors.white;
    TextStyle textStyle = TextStyle(
      color: profileColor,
      fontSize: 9,
    );
    String userProfileText = _userProfileName(context).replaceAll(' ', '\n');
    List<String> lines = userProfileText.split('\n');
    int maxLettersInLine = 0;
    for (String line in lines) {
      maxLettersInLine = max(maxLettersInLine, line.length);
    }
    double boxMinWidth = 26.0 + 7.0 * maxLettersInLine;
    if (userProfileText.length < 4) {
      boxMinWidth = 50;
    }
    Text textItem = Text(userProfileText, style: textStyle);
    Icon profileIcon = Icon(Icons.person_sharp, size: 22, color: profileColor);
    Container box = Container(
      child: Center(child: Row(children: [profileIcon,  textItem])),
      padding: EdgeInsets.fromLTRB(3, 0, 3, 0),
      width: boxMinWidth,
      constraints: BoxConstraints(
        maxWidth: 150,
        maxHeight: 26,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: profileColor.withAlpha(130)),
        borderRadius: BorderRadius.circular(8),
      ),
    );
    // MouseRegion pointable = MouseRegion(
    //   child: box, cursor: SystemMouseCursors.click,
    // );
    // GestureDetector clickable = GestureDetector(
    //   child: pointable,
    //   onTap: _showProfileActions,
    // );
    // return clickable;
    return PopupMenuButton(
      tooltip: 'Профиль и выход',
      itemBuilder: (BuildContext context) {
        List<PopupMenuEntry<Function>> result = [];
        result.add(PopupMenuItem<Function>(
          value: _goToProfile,
          child: Text('Профиль'),
        ));
        result.add(PopupMenuItem<Function>(
          value: _doLogout,
          child: Text('Выход'),
        ));
        return result;
      },
      onSelected: (Function action) {
        action();
      },
      child: box,
    );
  }


  EdgeInsets internalPadding() {
    return EdgeInsets.symmetric(horizontal: 8);
  }

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);
    TextStyle titleStyle = theme.textTheme.headline5!.merge(TextStyle(
      fontWeight: FontWeight.w500,
      color: Colors.white,
    ));
    // check for title text overflow on small screen
    TextPainter textPainter = TextPainter(
      maxLines: 1,
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      text: TextSpan(text: title, style: titleStyle),
    );
    double availableWidth = MediaQuery.of(context).size.width - 200;
    textPainter.layout(maxWidth: availableWidth);
    bool titleOverflow = textPainter.didExceedMaxLines;

    if (titleOverflow) {
      titleStyle = titleStyle.merge(TextStyle(
        fontSize: titleStyle.fontSize! * 0.7
      ));
    }

    List<TextSpan> titleWordSpans = List.empty(growable: true);
    List<String> titleWords = title.split(' ');
    for (String titleWord in titleWords) {
      if (titleWordSpans.isNotEmpty)
        titleWordSpans.add(TextSpan(text: ' '));
      titleWordSpans.add(TextSpan(text: titleWord));
    }
    Widget titleItem = Container(
        padding: EdgeInsets.fromLTRB(0, 0, 0, 0),
        width: MediaQuery.of(context).size.width - 200,
        child: Row(
          children: [
            Expanded(
              child: Text(title, style: titleStyle, maxLines: 2,),
            )
          ],
        )
      );
    Widget? userProfileItem = _buildUserProfileWidget(context);
    Drawer? drawer;
    Widget? navItem = buildNavigationWidget(context);
    Widget? body;
    Widget? central = buildCentralWidget(context);
    if (navItem != null && MediaQuery.of(context).size.width < leftNavigationWidthThreshold) {
      drawer = Drawer(
        child: navItem,
      );
      if (central != null) {
        body = SingleChildScrollView(
            child: Padding(child: central, padding: internalPadding())
        );
      }
    }
    else if (navItem != null && central != null) {
      body = Row(
        children: [
          _wrapNavigationFloatBoxPanelMaterial(navItem)!,
          Expanded(
              child: SingleChildScrollView(
                  child: Padding(child: central, padding: internalPadding())
              )
          )
        ],
      );
    }
    else if (central != null) {
      body = SingleChildScrollView(
          child: Padding(child: central, padding: internalPadding())
      );
    }
    final tabs = secondLevelNavigationTabs();
    List<Widget> tabWidgets = [];
    List<Tab> tabButtons = [];
    int selectedIndex = 0;
    int currentIndex = 0;
    Map<String, Widget Function(BuildContext context)> tabWidgetsByName = {};
    for (final tab in tabs) {
      final builder = tab.builder;
      // final tabWidget = builder(context);
      // tabWidgets.add(tabWidget);
      tabWidgetsByName[tab.id] = builder;
      tabButtons.add(Tab(
          text: tab.title,
          icon: tab.icon,
      ));
      if (widget.secondLevelTabId.isNotEmpty && tab.id==widget.secondLevelTabId) {
        selectedIndex = currentIndex;
      }
      currentIndex ++;
    }
    TabBar? tabBar = tabs.isEmpty? null : TabBar(
      tabs: tabButtons,
      controller: _secondLevelTabController,
      onTap: (index) {
        final tabData = tabs[index];
        List<String> currentPath = ModalRoute.of(context)!.settings.name!.split('/');
        String lastPart = currentPath.last;
        bool isTabLabel = false;
        for (final testTab in tabs) {
          if (testTab.id == lastPart) {
            isTabLabel = true;
          }
        }
        if (isTabLabel && tabData.id.isNotEmpty) {
          currentPath.removeLast();
          currentPath.add(tabData.id)
          String newPath = currentPath.join('/');
          // secondLevelNavigationKey.currentState!.pushReplacementNamed(tabData.id);
          setState(() {
            secondLevelNavigationKey.currentState!.pushReplacementNamed(tabData.id);
          });
          //
          // Navigator.pushReplacementNamed(context, newPath);
        }
      },
    );
    if (body == null && tabWidgets.isNotEmpty) {
      _secondLevelTabController!.index = selectedIndex;
      body = Navigator(
        key: secondLevelNavigationKey,
        initialRoute: widget.secondLevelTabId,
        onGenerateRoute: (RouteSettings settings) {
          return MaterialPageRoute(
            settings: settings,
            builder: tabWidgetsByName[settings.name!]!,
            // builder: (context) {
            //   return TabBarView(
            //   controller: _secondLevelTabController,
            //   children: tabWidgets,
            // );
          );
        }
      );
      log.fine('build screen base with inner navigator initial value ${widget.secondLevelTabId}');
    }
    List<Widget> titleRowItems = [titleItem];
    if (userProfileItem!=null) {
      titleRowItems.addAll([Spacer(), userProfileItem]);
    }
    Scaffold scaffold = Scaffold(
      appBar: AppBar(
        title: Row(children: titleRowItems),
        bottom: tabBar,
      ),
      body: body,
      bottomSheet: _buildSubmitBar(context),
      floatingActionButton: _buildFAB(context),
      drawer: drawer,
      drawerEnableOpenDragGesture: false,
    );
    return scaffold;
  }

  @protected
  Widget? buildCentralWidget(BuildContext context) => null;

  @protected
  ScreenActions? buildPrimaryScreenActions(BuildContext context) => null;

  @protected
  ScreenActions? buildSecondaryScreenActions(BuildContext context) => null;

  @protected
  ScreenSubmitAction? submitAction(BuildContext context) => null;

  Widget? buildNavigationWidget(BuildContext context) => null;

  Widget? _buildFAB(BuildContext context) {
    ScreenActions? primary = buildPrimaryScreenActions(context);
    ScreenActions? secondary = buildSecondaryScreenActions(context);
    ScreenActions? screenActions = secondary==null? primary : secondary;
    if (screenActions == null) {
      return null;
    }
    if (screenActions.actions.length > 0) {
      List<ActionButton> actionButtons = List.of(
          screenActions.actions.map((ScreenAction a) {
            return ActionButton(
              icon: a.icon,
              title: a.title,
              isPrimary: screenActions.isPrimaryActions,
              onPressed: a.onAction,
            );
          })
      );
      return ExpandableFab(
        distance: 100,
        children: actionButtons,
        mainIcon: screenActions.rootIcon,
        title: screenActions.rootTitle,
        isPrimary: screenActions.isPrimaryActions,
      );
    } else {
      return FloatingActionButton.extended(
        icon: screenActions.rootIcon,
        onPressed: screenActions.onRootAction,
        label: Text(screenActions.rootTitle),
      );
    }
  }


  Widget? _buildSubmitBar(BuildContext context) {
    List<Widget> items = List.empty(growable: true);
    ScreenSubmitAction? submit = submitAction(context);
    if (submit != null) {
      Color buttonColor;
      MouseCursor mouseCursor = SystemMouseCursors.click;
      if (submit.onAction == null) {
        // button disabled
        buttonColor = Theme.of(context).disabledColor.withAlpha(20);
        mouseCursor = SystemMouseCursors.basic;
      } else if (submit.color != null) {
        // use custom color
        buttonColor = submit.color!;
      } else {
        // use default color
        buttonColor = Theme.of(context).primaryColor;
      }
      items.add(ElevatedButton(
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.all<Color>(buttonColor),
          mouseCursor: MaterialStateProperty.all<MouseCursor>(mouseCursor),
        ),
        child: Container(
          height: 48,
          padding: EdgeInsets.all(8),
          child: Center(
            child: Text(submit.title, style: TextStyle(fontSize: 20, color: Colors.white))
          ),
        ),
        onPressed: submit.onAction,
      ));
    }
    if (items.length == 0) {
      return null;
    }
    return Container(
      child: Padding(
        child:Row(
          children: List.of(items.map((e) => Expanded(child: e))),
        ),
        padding: EdgeInsets.all(8),
      )
    );
  }

  Widget? _wrapNavigationFloatBoxPanelMaterial(Widget? child) {
    return Container(
      child: child,
      width: 450,
      height: MediaQuery.of(context).size.height - 56,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(
          color: Colors.black87
        ))
      ),
    );
  }

  List<SecondLevelNavigationTab> secondLevelNavigationTabs() => List.empty();

}