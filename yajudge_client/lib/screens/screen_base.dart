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
  final Icon cupertinoIcon;
  final String title;
  final Function() onAction;

  ScreenAction({
    required this.icon,
    required this.title,
    required this.onAction,
    Icon? cupertinoIcon,
  })
      : this.cupertinoIcon = cupertinoIcon!=null ? cupertinoIcon : icon;

}

class ScreenActions {
  final Icon rootIcon;
  final Icon rootIconCupertino;
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
    Icon? rootIconCupertino,
    bool? isPrimary,
    Function()? onRoot,
    List<ScreenAction>? actions,
  })
      : isPrimaryActions = isPrimary!=null? isPrimary : true,
        onRootAction = onRoot,
        this.actions = actions!=null? actions : List.empty(),
        this.rootIconCupertino = rootIconCupertino!=null
            ? rootIconCupertino
            : rootIcon
  ;
}

abstract class BaseScreenState extends State<BaseScreen> {
  String title;
  late RpcConnectionState _rpcConnectionState;
  final bool isLoginScreen;
  final bool isFirstScreen;
  late final bool isCupertino;

  BaseScreenState({required String title, bool? isLoginScreen, bool? isFirstScreen})
      : this.title = title,
        this.isLoginScreen = isLoginScreen!=null? isLoginScreen : false,
        this.isFirstScreen = isFirstScreen!=null? isFirstScreen : false,
        super()
  ;

  @override
  void initState() {
    super.initState();
    isCupertino = PlatformsUtils.getInstance().isCupertino;
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

  @override
  Widget build(BuildContext context) {
    if (isCupertino) {
      return _buildCupertino(context);
    } else {
      return _buildMaterial(context);
    }
  }

  String _userProfileName(BuildContext context) {
    if (AppState.instance.userProfile == null) {
      return '';
    }
    String visibleName;
    double screenWidth = MediaQuery.of(context).size.width;
    final double ShortNameWidth = 500;
    User user = AppState.instance.userProfile!;
    if (user.firstName != null &&
        user.firstName!.isNotEmpty &&
        user.lastName != null &&
        user.lastName!.isNotEmpty)
    {
      if (screenWidth < ShortNameWidth) {
        visibleName = user.firstName![0] + user.lastName![0];
      } else {
        visibleName = user.firstName! + ' ' + user.lastName!;
      }
    } else {
      if (screenWidth < ShortNameWidth) {
        visibleName = user.id.toString();
      } else {
        visibleName = 'ID (' + user.id.toString() + ')';
      }
    }
    return visibleName;
  }


  bool _middleCupertinoTextIsTitle = false;
  void _changeCupertinoLargeTextVisibility(VisibilityInfo visibilityInfo) {
    if (!this.mounted) {
      _middleCupertinoTextIsTitle = false;
      return;
    }
    var visiblePercentage = visibilityInfo.visibleFraction * 100;
    if (visiblePercentage < 8 && !_middleCupertinoTextIsTitle) {
      setState(() {
        _middleCupertinoTextIsTitle = true;
      });
    } else if (visiblePercentage >= 8 && _middleCupertinoTextIsTitle) {
      setState(() {
        _middleCupertinoTextIsTitle = false;
      });
    }
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
    if (isCupertino) {
      showCupertinoDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) {
          return CupertinoAlertDialog(
            actions: actions,
          );
        }
      );
    } else {
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
  }

  Widget _buildUserProfileWidgetCupertino(BuildContext context) {
    Color profileColor;
    if (_rpcConnectionState == RpcConnectionState.Connected) {
      profileColor = Theme.of(context).primaryColor;
    } else {
      profileColor = Theme.of(context).errorColor;
    }
    TextStyle textStyle = TextStyle(
      color: profileColor,
      fontSize: 14,
    );
    Text textItem = Text(_userProfileName(context), style: textStyle);
    MouseRegion pointable = MouseRegion(
      child: textItem, cursor: SystemMouseCursors.click,
    );
    GestureDetector clickable = GestureDetector(
      child: pointable,
      onTap: _showProfileActions,
    );
    return clickable;
  }

  Widget _buildUserProfileWidgetMaterial(BuildContext context) {
    TextStyle textStyle = TextStyle(
      color: Colors.white,
      fontSize: 18,
    );
    Text textItem = Text(_userProfileName(context), style: textStyle);
    MouseRegion pointable = MouseRegion(
      child: textItem, cursor: SystemMouseCursors.click,
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

  final double leftNavigationWidthThreshold = 550;
  final double leftNavigationPadding = 320;

  Widget _buildCupertino(BuildContext context) {

    Widget central = buildCentralWidgetCupertino(context);
    Widget titleItem = Text(title);
    Widget userProfileItem = _buildUserProfileWidgetCupertino(context);

    double leftPadding = internalPadding().left;
    Widget? navigationWidget = buildNavigationWidget(context);
    if (navigationWidget != null && MediaQuery.of(context).size.width > leftNavigationWidthThreshold) {
      leftPadding = leftNavigationPadding;
    }
    Widget largeTitleWithVisibilityDetector = VisibilityDetector(
      child: titleItem,
      key: Key('large-title-for-'+title),
      onVisibilityChanged: _changeCupertinoLargeTextVisibility,
    );

    Widget topNavigationBar = CupertinoSliverNavigationBar(
      largeTitle: largeTitleWithVisibilityDetector,
      middle: _middleCupertinoTextIsTitle? titleItem : userProfileItem,
      trailing: _buildCupertinoTrailingToolbar(context),
    );

    Widget mainArea = SliverToBoxAdapter(
        child: Padding(
          child: central,
          padding: internalPadding().copyWith(left: leftPadding),
        )
    );

    Widget scaffold = CupertinoPageScaffold(child: CustomScrollView(slivers: [
      topNavigationBar, mainArea
    ]));

    List<Widget> topLevelScreenItems = [scaffold];

    if (navigationWidget != null && MediaQuery.of(context).size.width > leftNavigationWidthThreshold) {
      topLevelScreenItems.add(Positioned(
        top: 130,
        left: 20,
        bottom: 60,
        child: _wrapNavigationFloatBoxPanel(navigationWidget)!,
      ));
    }

    return Stack(children: topLevelScreenItems);
  }


  Widget _buildMaterial(BuildContext context) {
    Widget central = buildCentralWidgetMaterial(context);
    Widget titleItem = Text(title);
    Widget statusItem = Padding(
      padding: EdgeInsets.all(8),
      child: Icon(
        Icons.circle,
        color: _rpcConnectionState == RpcConnectionState.Connected
            ? Theme.of(context).appBarTheme.color
            : Theme.of(context).errorColor,
        size: 8.0,
      ),
    );
    Widget userProfileItem = _buildUserProfileWidgetMaterial(context);
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
    return Scaffold(
      appBar: AppBar(title: Row(children: [
        titleItem, Spacer(), userProfileItem, statusItem
      ])),
      body: body,
      bottomSheet: _buildMaterialSubmitBar(context),
      floatingActionButton: _buildMaterialFAB(context),
      drawer: drawer,
      drawerEnableOpenDragGesture: false,
    );
  }

  Widget buildCentralWidgetCupertino(BuildContext context) ;
  Widget buildCentralWidgetMaterial(BuildContext context) ;
  ScreenActions? buildPrimaryScreenActions(BuildContext context) => null;
  ScreenActions? buildSecondaryScreenActions(BuildContext context) => null;
  ScreenSubmitAction? submitAction(BuildContext context) => null;

  Widget? buildNavigationWidget(BuildContext context) => null;

  Widget? _buildMaterialFAB(BuildContext context) {
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

  Widget _actionItemToCupertinoIcon(BuildContext context, ScreenAction a, bool primary) {
    return Material(child:
      IconButton(
        onPressed: a.onAction,
        icon: a.cupertinoIcon,
        tooltip: a.title,
        color: primary? Theme.of(context).primaryColor : Colors.deepOrange,
      )
    );
  }

  Widget? _buildCupertinoTrailingToolbar(BuildContext context) {
    ScreenActions? primary = buildPrimaryScreenActions(context);
    ScreenActions? secondary = buildSecondaryScreenActions(context);
    ScreenSubmitAction? submit = submitAction(context);
    if (primary==null && secondary==null && submit==null) {
      return null;
    }
    List<Widget> items = List.empty(growable: true);
    items.add(Spacer());
    if (secondary != null && secondary.actions.length > 0) {
      items.addAll(secondary.actions.map((e) => _actionItemToCupertinoIcon(context, e, false)));
    } else if (secondary != null) {
      items.add(_actionItemToCupertinoIcon(context, secondary.rootAction!, false));
    }
    if (primary != null && primary.actions.length > 0) {
      items.addAll(primary.actions.map((e) => _actionItemToCupertinoIcon(context, e, true)));
    } else if (primary != null) {
      items.add(_actionItemToCupertinoIcon(context, primary.rootAction!, true));
    }
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
      items.add(OutlinedButton(
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
    return Container(
      constraints: BoxConstraints(maxWidth: 150),
      child: Row(children: items)
    );
  }

  Widget? _buildMaterialSubmitBar(BuildContext context) {
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

}