import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/widgets.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:yajudge_client/utils/utils.dart';
import 'package:yajudge_client/widgets/expandable_fab.dart';
import 'package:yajudge_client/widgets/unified_widgets.dart';
import 'package:yajudge_client/wsapi/connection.dart';
import 'package:yajudge_client/wsapi/users.dart';

import '../app.dart';

abstract class BaseScreen extends StatefulWidget {
  BaseScreen({Key? key}) : super(key: key) ;
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
  final String title;
  final Icon icon;
  final Widget Function(BuildContext context) builder;

  SecondLevelNavigationTab(this.title, this.icon, this.builder);
}

abstract class BaseScreenState extends State<BaseScreen> {
  String title;
  late RpcConnectionState _rpcConnectionState;
  final bool isLoginScreen;
  final bool isFirstScreen;

  final double leftNavigationWidthThreshold = 750;
  final double shortProfileNameWidthThreshold = 750;
  final double leftNavigationPadding = 320;

  BaseScreenState({required String title, bool? isLoginScreen, bool? isFirstScreen})
      : this.title = title,
        this.isLoginScreen = isLoginScreen!=null? isLoginScreen : false,
        this.isFirstScreen = isFirstScreen!=null? isFirstScreen : false,
        super()
  ;

  @override
  void initState() {
    super.initState();
    RpcConnection connection = RpcConnection.getInstance();
    _rpcConnectionState = connection.getState();
    connection.registerChangeStateCallback((state) {
      _setConnectionState(state);
    });
    WidgetsBinding.instance!.addPostFrameCallback((timeStamp) {
      if (AppState.instance.sessionId.isEmpty && !isLoginScreen) {
          setState(() {
            Navigator.pushReplacementNamed(context, '/login');
          }
        );
      }
    });
  }

  @override
  void dispose() {
    RpcConnection connection = RpcConnection.getInstance();
    connection.registerChangeStateCallback(null);
    super.dispose();
  }

  void _setConnectionState(RpcConnectionState st) {
    setState(() {
      _rpcConnectionState = st;
    });
  }

  String _userProfileName(BuildContext context) {
    if (AppState.instance.userProfile == null) {
      return '';
    }
    String visibleName;
    double screenWidth = MediaQuery.of(context).size.width;
    User user = AppState.instance.userProfile!;
    if (user.firstName != null &&
        user.firstName!.isNotEmpty &&
        user.lastName != null &&
        user.lastName!.isNotEmpty)
    {
      if (screenWidth < shortProfileNameWidthThreshold) {
        visibleName = user.firstName![0] + user.lastName![0];
      } else {
        visibleName = user.firstName! + ' ' + user.lastName!;
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
    AppState app = AppState.instance;
    app.sessionId = '';
    Navigator.pushReplacementNamed(context, '/login');
  }

  void _goToProfile() {
    Navigator.pushNamed(context, '/users/myself');
  }

  void _showProfileActions() {
    List<Widget> actions = [
      YTextButton('Профиль', () {
        Navigator.pop(context);
        _goToProfile();
      }, fontSize: 18),
      YTextButton('Выйти', () {
        Navigator.pop(context);
        _doLogout();
      }, color: Colors.red, fontSize: 18)
    ];
    showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) {
          return AlertDialog(content: Container(
            height: 100,
            child: Center(child: Column(children: actions)),
          ));
        }
    );
  }

  Widget _buildUserProfileWidget(BuildContext context) {
    Color profileColor;
    if (_rpcConnectionState == RpcConnectionState.Connected) {
      profileColor = Colors.white;
    } else {
      profileColor = Theme.of(context).errorColor;
    }
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
    MouseRegion pointable = MouseRegion(
      child: box, cursor: SystemMouseCursors.click,
    );
    GestureDetector clickable = GestureDetector(
      child: pointable,
      onTap: _showProfileActions,
    );
    return clickable;
  }
  

  EdgeInsets internalPadding() {
    return EdgeInsets.symmetric(horizontal: 8);
  }

  @override
  Widget build(BuildContext context) {
    Widget central = buildCentralWidget(context);
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
    int titleMaxLines = 1;
    bool softWrap = false;
    if (titleOverflow) {
      titleStyle = titleStyle.merge(TextStyle(
        fontSize: titleStyle.fontSize! * 0.7
      ));
      titleMaxLines = 2;
      softWrap = true;
    }
    List<TextSpan> titleWordSpans = List.empty(growable: true);
    List<String> titleWords = title.split(' ');
    for (String titleWord in titleWords) {
      if (titleWordSpans.isNotEmpty)
        titleWordSpans.add(TextSpan(text: ' '));
      titleWordSpans.add(TextSpan(text: titleWord));
    }
    Widget titleItem =
      Container(
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
    Widget userProfileItem = _buildUserProfileWidget(context);
    Drawer? drawer;
    Widget? navItem = buildNavigationWidget(context);
    late Widget body;
    if (navItem != null && MediaQuery.of(context).size.width < leftNavigationWidthThreshold) {
      drawer = Drawer(
        child: navItem,
      );
      body = SingleChildScrollView(
          child: Padding(child: central, padding: internalPadding())
      );
    } else if (navItem != null) {
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
    } else {
      body = SingleChildScrollView(
          child: Padding(child: central, padding: internalPadding())
      );
    }
    List<Tab> tabs = List.empty(growable: true);
    for (SecondLevelNavigationTab tabData in secondLevelNavigationTabs()) {
      tabs.add(Tab(text: tabData.title, icon: tabData.icon));
    }
    TabBar? tabBar = tabs.isEmpty? null : TabBar(tabs: tabs);
    Scaffold scaffold = Scaffold(
      appBar: AppBar(
        title: Row(children: [titleItem, Spacer(), userProfileItem]),
        bottom: tabBar,
      ),
      body: body,
      bottomSheet: _buildSubmitBar(context),
      floatingActionButton: _buildFAB(context),
      drawer: drawer,
      drawerEnableOpenDragGesture: false,
    );
    DefaultTabController tabController = DefaultTabController(
        length: tabs.length,
        child: scaffold
    );
    return tabController;
  }

  @protected
  Widget buildCentralWidget(BuildContext context) ;

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
        child: Text(submit.title,
          style: TextStyle(
            // fontSize: 11
              color: Colors.white
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

  Widget? _wrapNavigationFloatBoxPanel(Widget? child) {
    return Container(
      child: child,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        color: Color.fromARGB(255, 250, 250, 250),
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  Widget? _wrapNavigationFloatBoxPanelMaterial(Widget? child) {
    return Container(
      child: child,
      width: 330,
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