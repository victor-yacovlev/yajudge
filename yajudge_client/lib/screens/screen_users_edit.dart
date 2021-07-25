import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:flutter/widgets.dart';
import 'package:yajudge_client/app.dart';
import 'package:yajudge_client/screens/screen_base.dart';
import 'package:yajudge_client/widgets/unified_widgets.dart';
import 'package:yajudge_client/wsapi/users.dart';


class UsersEditScreen extends BaseScreen {
  final String userIdOrNewOrMyself;

  UsersEditScreen(this.userIdOrNewOrMyself): super() ;

  @override
  State<StatefulWidget> createState() => UserEditScreenState();

}

class UserEditScreenState extends BaseScreenState {

  UserEditScreenState() : super(title: 'Профиль пользователя');
  String? _errorString;
  String? _statusText;

  bool get isAdministrator {
    User myself = AppState.instance.userProfile!;
    return myself.defaultRole == UserRole_Administrator;
  }

  bool get isMyself {
    if (_user == null) {
      return false;
    }
    User myself = AppState.instance.userProfile!;
    return userId != null && myself.id == userId!;
  }

  int? get userId {
    UsersEditScreen editScreen = widget as UsersEditScreen;
    String arg = editScreen.userIdOrNewOrMyself;
    if (arg == 'new') {
      return null;
    }
    if (arg == 'myself') {
      return AppState.instance.userProfile!.id;
    }
    int? id = int.tryParse(arg, radix: 10);
    if (id == null) {
      _errorString = 'Неправильный аргумент';
      return null;
    }
    return id;
  }

  User? _user;

  void _loadUserProfile() {
    int? uid = userId;
    if (uid == null) {
      return;
    }
    UsersService service = UsersService.instance;
    UsersFilter usersFilter = UsersFilter();
    usersFilter.user = User()..id=uid;
    service.getUsers(usersFilter).then((UsersList usersList) {
      if (usersList.users.length == 0) {
        setState(() {
          _errorString = 'Нет пользователя с таким ID';
          _user = null;
        });
      } else {
        assert (usersList.users.length == 1);
        setState(() {
          _errorString = null;
          _user = usersList.users[0];
          _roleController.text = '';
          _emailController.text = '';
          _firstNameController.text = '';
          _lastNameController.text = '';
          _midNameController.text = '';
          _groupNameController.text = '';
          _passwordController.text = '';
        });
      }
    }).onError((error, stackTrace) {
      setState(() {
        _errorString = error.toString();
        _user = null;
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  TextEditingController _userIdController = TextEditingController();
  TextEditingController _lastNameController = TextEditingController();
  TextEditingController _firstNameController = TextEditingController();
  TextEditingController _midNameController = TextEditingController();
  TextEditingController _groupNameController = TextEditingController();
  TextEditingController _emailController = TextEditingController();
  TextEditingController _passwordController = TextEditingController();
  static final Map<int, String> RoleNames = {
    UserRole_Any: '[ не назначена ]',
    UserRole_Administrator: 'Администратор',
    UserRole_Lecturer: 'Лектор',
    UserRole_Teacher: 'Семинарист',
    UserRole_TeacherAssistant: 'Учебный ассистент',
    UserRole_Student: 'Студент',
  };
  TextEditingController _roleController = TextEditingController();

  Widget _buildFieldItem(
      BuildContext context, String label, TextEditingController controller,
      String value, bool editable, {Widget? actionWidget, String? hintText} )
  {
    if (controller.text.isEmpty) {
      controller.text = value;
    }

    List<Widget> rowItems = List.empty(growable: true);
    rowItems.add(Container(
      width: 150,
      margin: EdgeInsets.fromLTRB(0, 0, 10, 0),
      child: Text(label+':', textAlign: TextAlign.end),
    ));
    rowItems.add(Expanded(
        child: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: hintText),
          focusNode: editable? null : AlwaysDisabledFocusNode(),
          style: TextStyle(
            color: editable
                ? Theme.of(context).textTheme.bodyText1!.color
                : Theme.of(context).disabledColor,
          ),
          onChanged: (_) => setState(() {_checkIsCanSubmit();}),
        )
    ));
    if (actionWidget != null) {
      rowItems.add(Container(
        width: 100,
        child: actionWidget,
      ));
    }
    return Container(
        child: Row(
            children: rowItems
        )
    );
  }

  void _resetPassword() {
    UsersService service = UsersService.instance;
    service.resetUserPassword(_user!).then((User changed) {
      setState(() {
        _errorString = null;
        _user = changed;
        _passwordController.text = changed.password!;
      });
    }).onError((error, stackTrace) {
      setState(() {
        _errorString = error.toString();
      });
    });
  }

  void _changePassword() {
    if (_passwordController.text.trim().isEmpty) {
      setState(() {
        _errorString = 'Пароль не может быть пустым';
        _statusText = null;
      });
      return;
    }
    _user!.password = _passwordController.text.trim();
    UsersService service = UsersService.instance;
    service.changePassword(_user!).then((User changed) {
      setState(() {
        _errorString = null;
        _user = changed;
        _statusText = 'Пароль успешно изменен';
        _passwordController.text = '';
      });
    }).onError((error, stackTrace) {
      setState(() {
        _errorString = error.toString();
        _statusText = null;
      });
    });
  }

  int _roleByName(String name) {
    assert (RoleNames.containsValue(name));
    for (MapEntry<int,String> e in RoleNames.entries) {
      if (e.value == name) {
        return e.key;
      }
    }
    return UserRole_Any;
  }

  void _pickRole() {
    var builder = (BuildContext context) {
      List<Widget> roleItems = List.empty(growable: true);
      for (MapEntry<int,String> e in RoleNames.entries) {
        if (e.key != UserRole_Any) {
          roleItems.add(YTextButton(e.value, () {
            setState(() {
              _roleController.text = e.value;
              _checkIsCanSubmit();
            });
            Navigator.of(context).pop();
          }));
        }
      }
      return AlertDialog(
          content: Container(
            child: Center(
              child: Column(
                children: roleItems,
              ),
            ),
            height: 140,
          ),
          actions: []
      );
    };
    showDialog(context: context, builder: builder);
  }

  String generateRandomPassword() {
    final String alphabet = '0123456789abcdef';
    String password = '';
    Random random = Random.secure();
    for (int i=0; i<8; i++) {
      int runeNum = random.nextInt(alphabet.length);
      String rune = alphabet[runeNum];
      password += rune;
    }
    return password;
  }

  @override
  Widget buildCentralWidgetCupertino(BuildContext context) {
    return _buildCentralWidgetUnified(context);
  }

  @override
  Widget _buildCentralWidgetUnified(BuildContext context) {
    List<Widget> items = List.empty(growable: true);
    if (!isAdministrator) {
      items.add(Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text(
          'Некоторые поля нельзя изменить.'
          ' Обратитесь к лектору курса, если обнаружите неточности.')
      ));
    }
    if (_user != null) {
      items.add(_buildFieldItem(context, 'ID пользователя', _userIdController, _user!.id.toString(), false));
    }

    items.add(_buildFieldItem(context, 'Фамилия', _lastNameController, _user==null? '' : _user!.lastName!, isAdministrator));
    items.add(_buildFieldItem(context, 'Имя', _firstNameController, _user==null? '' : _user!.firstName!, isAdministrator));
    items.add(_buildFieldItem(context, 'Отчество', _midNameController, _user==null || _user!.midName==null ? '' : _user!.midName!, isAdministrator));
    items.add(_buildFieldItem(context, 'Группа', _groupNameController, _user==null || _user!.groupName==null ? '' : _user!.groupName!, isAdministrator));
    items.add(_buildFieldItem(context, 'EMail', _emailController, _user==null || _user!.email==null ? '' : _user!.email!, isAdministrator));

    String passwordValue = '';
    String? passwordHint = '';
    bool passwordEditable = false;
    YTextButton? passwordActionButton = null;
    if (isMyself) {
      passwordEditable = true;
      if (_user!.password!=null && _user!.password!.isNotEmpty) {
        passwordValue = _user!.password!;
        passwordHint = null;
      } else {
        passwordValue = '';
        passwordHint = 'Не отображается, но можно изменить';
      }
      passwordActionButton = YTextButton('Изменить', _changePassword);
    } else if (isAdministrator && _user!=null) {
      passwordEditable = false;
      if (_user!.password!=null && _user!.password!.isNotEmpty) {
        passwordValue = _user!.password!;
        passwordHint = null;
      } else {
        passwordValue = '';
        passwordHint = 'Пароль был изменен пользователем';
      }
      passwordActionButton = YTextButton('Сбросить', _resetPassword);
    } else if (_user == null) {
      passwordValue = generateRandomPassword();
    }
    items.add(_buildFieldItem(context, 'Пароль', _passwordController,
        passwordValue, passwordEditable,
        hintText: passwordHint,
        actionWidget: passwordActionButton));


    YTextButton? roleActionButton = null;
    String roleName = '';
    if (isAdministrator) {
      roleActionButton = YTextButton('Изменить', _pickRole);
    }
    if (_user == null) {
      if (_roleController.text.trim().isNotEmpty)
        roleName = _roleController.text.trim();
      else
        roleName = RoleNames[UserRole_Student]!;
    } else {
      roleName = RoleNames[_user!.defaultRole]!;
    }
    items.add(_buildFieldItem(context, 'Роль по умолчанию',
        _roleController, roleName, false,
        actionWidget: roleActionButton
    ));

    if (_errorString != null) {
      items.add(Padding(padding: EdgeInsets.all(10), child: Text(
        _errorString!,
        style: TextStyle(color: Theme.of(context).errorColor),
      )));
    }
    if (_statusText != null) {
      items.add(Padding(padding: EdgeInsets.all(10), child: Text(
        _statusText!,
        style: TextStyle(color: Theme.of(context).primaryColor),
      )));
    }

    return Column(children: items);
  }

  @override
  Widget buildCentralWidget(BuildContext context) {
    return _buildCentralWidgetUnified(context);
  }

  bool _isSubmitting = false;
  bool _canSubmit = false;

  void _submit() {
    setState(() {
      _isSubmitting = true;
    });
    User user;
    if (_user != null) {
      user = _user!;
    } else {
      user = User()..id = 0;
    }
    user.firstName = _firstNameController.text.trim();
    user.lastName = _lastNameController.text.trim();
    user.midName = _midNameController.text.trim();
    user.groupName = _groupNameController.text.trim();
    user.password = _passwordController.text.trim();
    user.email = _emailController.text.trim();
    user.defaultRole = _roleByName(_roleController.text.trim());
    user.disabled = false;
    UsersService service = UsersService.instance;
    service.createOrUpdateUser(user).then((changedUser) {
      setState(() {
        _user = changedUser;
        _errorString = null;
        Navigator.pop(context);
      });
      Future.delayed(Duration(milliseconds: 500), () {
        if (!mounted)
          return;
        setState(() {
          _isSubmitting = false;
        });
      });
    }).onError((error, stackTrace) {
      setState(() {
        _errorString = error.toString();
      });
      Future.delayed(Duration(milliseconds: 500), () {
        if (!mounted)
          return;
        setState(() {
          _isSubmitting = false;
        });
      });
    });
  }

  void _checkIsCanSubmit() {
    bool canSubmit = false;
    bool firstNameSet = _firstNameController.text.trim().isNotEmpty;
    bool lastNameSet = _lastNameController.text.trim().isNotEmpty;
    bool passwordSet = _user != null;
    if (_user == null) {
      passwordSet = _passwordController.text.trim().isNotEmpty;
      canSubmit = firstNameSet && lastNameSet && passwordSet;
    } else {
      int newRole = _roleByName(_roleController.text.trim());
      bool firstNameChanged = _user!.firstName != _firstNameController.text.trim();
      bool lastNameChanged = _user!.lastName != _lastNameController.text.trim();
      bool midNameChanged = _user!.midName != _midNameController.text.trim();
      bool groupNameChanged = _user!.groupName != _groupNameController.text.trim();
      bool emailChanged = _user!.email != _emailController.text.trim();
      bool roleChanged = _user!.defaultRole != newRole;
      bool changed =
          firstNameChanged || lastNameChanged || midNameChanged ||
              groupNameChanged || emailChanged || roleChanged
      ;
      canSubmit = firstNameSet && lastNameSet && passwordSet && changed;
    }
    _canSubmit = canSubmit;
  }

  ScreenSubmitAction? submitAction(BuildContext context) {
    if (!_canSubmit) {
      return null;
    }
    ScreenSubmitAction action = ScreenSubmitAction(
      title: 'Сохранить',
      onAction: _isSubmitting ? null : _submit
    );
    return action;
  }

}