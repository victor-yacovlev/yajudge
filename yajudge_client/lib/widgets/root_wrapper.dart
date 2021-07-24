import 'package:flutter/cupertino.dart';
import 'package:yajudge_client/screens/screen_dashboard.dart';
import 'package:yajudge_client/utils/utils.dart';

import '../app.dart';
import '../screens/screen_login.dart';
import '../wsapi/connection.dart';
import '../wsapi/users.dart';
import 'package:flutter/material.dart';

class RootWrapper extends StatefulWidget {
  Widget _child;
  String _title;

  RootWrapper({required Widget child, required String title, Key? key})
      : _child = child,
        _title = title,
        super(key: key);

  @override
  State<StatefulWidget> createState() {
    RootWrapperState widgetState = RootWrapperState(child: _child, title: _title);
    RpcConnection connection = RpcConnection.getInstance();
    connection.registerChangeStateCallback((state) {
      widgetState.setConnectionState(state);
    });
    return widgetState;
  }

}

class RootWrapperState extends State<RootWrapper> {
  Widget _child;
  String _title;
  List<Widget>? _actionButtons;
  List<Widget?>? _mainActionButtonWrap;
  RpcConnectionState _rpcConnectionState =
      RpcConnection.getInstance().getState();

  RootWrapperState({required Widget child, required String title,
    List<Widget>? bottomActionButtons, List<Widget?>? mainActionButtonWrap})
      : _child = child,
        _actionButtons = bottomActionButtons,
        _mainActionButtonWrap = mainActionButtonWrap,
        _title = title;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance!.addPostFrameCallback((timeStamp) {
      if (AppState.instance.sessionId.isEmpty &&
          _child.runtimeType != LoginScreen) {
        setState(() {
          Navigator.pushReplacementNamed(context, '/login');
        });
      }
    });
  }

  @override
  void dispose() {
    RpcConnection connection = RpcConnection.getInstance();
    connection.registerChangeStateCallback(null);
    super.dispose();
  }


  void setConnectionState(RpcConnectionState st) {
    setState(() {
      _rpcConnectionState = st;
    });
  }

  @override
  Widget build(BuildContext context) {
    String userProfile;
    if (AppState.instance.userProfile != null) {
      User user = AppState.instance.userProfile!;
      String visibleName;
      double screenWidth = MediaQuery.of(context).size.width;
      final double ShortNameWidth = 500;
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
      userProfile = visibleName;
    } else {
      userProfile = '';
    }
    bool isCupertino = PlatformsUtils.getInstance().isCupertino;
    Widget titleItem = Text(_title);
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

    if (isCupertino) {
      Widget userProfileItem = Text(userProfile, style: TextStyle(
        color: _rpcConnectionState == RpcConnectionState.Connected
            ? Theme.of(context).primaryColor
            : Theme.of(context).errorColor
      ));
      bool removeBackNavigation = _child is LoginScreen || _child is DashboardScreen;
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: titleItem,
          trailing: userProfileItem,
          leading: removeBackNavigation? Text('') : null,
        ),
        child: Container(
          padding: EdgeInsets.fromLTRB(0, 44, 0, 0),
          child: _child,
        ),
      );
    } else {
      Widget userProfileItem = Text(userProfile);
      return Scaffold(
        appBar: AppBar(title: Row(children: [
          titleItem, Spacer(), userProfileItem, statusItem
        ])),
        body: Padding(child: _child, padding: EdgeInsets.all(8)),
      );
    }

  }

}
