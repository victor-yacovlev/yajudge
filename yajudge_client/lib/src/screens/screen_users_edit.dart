import 'dart:math';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../client_app.dart';
import '../controllers/connection_controller.dart';
import 'screen_base.dart';
import '../widgets/unified_widgets.dart';
import 'package:yajudge_common/yajudge_common.dart';


class UsersEditScreen extends BaseScreen {
  final String userIdOrNewOrMyself;

  UsersEditScreen({
    required User loggedInUser,
    required this.userIdOrNewOrMyself,
  }): super(loggedUser: loggedInUser) ;

  @override
  State<StatefulWidget> createState() => UserEditScreenState();

}

class UserEditScreenState extends BaseScreenState {

  UserEditScreenState() : super(title: 'Профиль пользователя');
  String _errorString = '';
  String _statusText = '';

  bool get isMyself {
    if (_user.id == 0) {
      return false;
    }
    User myself = widget.loggedUser;
    return myself.id == userId;
  }

  Int64 get userId {
    UsersEditScreen editScreen = widget as UsersEditScreen;
    String arg = editScreen.userIdOrNewOrMyself;
    if (arg == 'new') {
      return Int64();
    }
    if (arg == 'myself') {
      return widget.loggedUser.id;
    }
    int? id = int.tryParse(arg, radix: 10);
    if (id == null) {
      _errorString = 'Неправильный аргумент';
      return Int64();
    }
    return Int64(id);
  }

  late User _user;

  void _loadUserProfile() {
    final screen = widget as UsersEditScreen;
    if (screen.userIdOrNewOrMyself == 'new') {
      _user = User();
      return;
    }
    else if (screen.userIdOrNewOrMyself == 'myself') {
      _user = screen.loggedUser;
      return;
    }
    int? userId = int.tryParse(screen.userIdOrNewOrMyself);
    if (userId == null) {
      Navigator.pushReplacementNamed(context, '/users/myself');
    }
    UserManagementClient service = ConnectionController.instance!.usersService;
    UsersFilter usersFilter = UsersFilter();
    usersFilter.user = User()..id=Int64(userId!);
    service.getUsers(usersFilter).then((UsersList usersList) {
      if (usersList.users.length == 0) {
        setState(() {
          _errorString = 'Нет пользователя с таким ID';
          _user = User();
        });
      } else {
        assert (usersList.users.length == 1);
        setState(() {
          _errorString = '';
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
        _user = User();
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _user = User();
    _loadUserProfile();
  }

  TextEditingController _userIdController = TextEditingController();
  TextEditingController _lastNameController = TextEditingController();
  TextEditingController _firstNameController = TextEditingController();
  TextEditingController _midNameController = TextEditingController();
  TextEditingController _groupNameController = TextEditingController();
  TextEditingController _emailController = TextEditingController();
  TextEditingController _passwordController = TextEditingController();
  static final Map<Role, String> RoleNames = {
    Role.ROLE_ANY: '[ не назначена ]',
    Role.ROLE_ADMINISTRATOR: 'Администратор',
    Role.ROLE_LECTUER: 'Лектор',
    Role.ROLE_TEACHER: 'Семинарист',
    Role.ROLE_TEACHER_ASSISTANT: 'Учебный ассистент',
    Role.ROLE_STUDENT: 'Студент',
  };
  TextEditingController _roleController = TextEditingController();

  Widget _buildFieldItem(
      BuildContext context, String label, Widget child,
      {List<Widget> actionWidgets = const []})
  {
    List<Widget> rowItems = List.empty(growable: true);
    rowItems.add(Container(
      width: 150,
      margin: EdgeInsets.fromLTRB(0, 0, 10, 0),
      child: Text(label+':', textAlign: TextAlign.end),
    ));
    rowItems.add(Expanded(child: child));
    if (actionWidgets.isNotEmpty) {
      rowItems.add(Container(
        constraints: BoxConstraints(minWidth: 100),
        child: Row(children: actionWidgets),
      ));
    }
    return Container(
        child: Row(
            children: rowItems
        )
    );
  }

  Widget _buildDropdownFieldItem(
      BuildContext context, String label, List<String> values, TextEditingController controller,
      String value, bool editable, {List<Widget> actionWidgets = const [], String? hintText} )
  {
    if (controller.text.isEmpty) {
      controller.text = value;
    }
    final items = values
        .map((e) => DropdownMenuItem<String>(child: Text(e), value: e))
        .toList();
    final dropdown = DropdownButtonFormField(
      items: items,
      value: value,
      onChanged: editable? (String? newValue) {
        if (newValue != null) {
          controller.text = newValue;
        }
      } : null,
    );
    return _buildFieldItem(context, label, dropdown, actionWidgets: actionWidgets);
  }

  Widget _buildTextFieldItem(
      BuildContext context, String label, TextEditingController controller,
      String value, bool editable, {List<Widget> actionWidgets = const [], String? hintText} )
  {
    if (controller.text.isEmpty) {
      controller.text = value;
    }
    final textField = TextField(
      controller: controller,
      enableInteractiveSelection: true,
      decoration: InputDecoration(hintText: hintText),
      focusNode: editable? null : AlwaysDisabledFocusNode(),
      style: TextStyle(
        color: editable
            ? Theme.of(context).textTheme.bodyText1!.color
            : Theme.of(context).disabledColor,
      ),
      onChanged: (_) => setState(() {_checkIfCanSubmit();}),
    );
    return _buildFieldItem(context, label, textField, actionWidgets: actionWidgets);
  }

  void _resetPassword() {
    UserManagementClient service = ConnectionController.instance!.usersService;
    service.resetUserPassword(_user).then((changed) {
      setState(() {
        _errorString = '';
        _user = changed;
        _passwordController.text = changed.password;
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
        _statusText = '';
      });
      return;
    }
    _user.password = _passwordController.text.trim();
    UserManagementClient service = ConnectionController.instance!.usersService;
    service.changePassword(_user).then((changed) {
      setState(() {
        _errorString = '';
        _user = changed;
        _statusText = 'Пароль успешно изменен';
        _passwordController.text = '';
      });
    }).onError((error, stackTrace) {
      setState(() {
        _errorString = error.toString();
        _statusText = '';
      });
    });
  }

  void _copyPasswordToClipboard() {
    final passwordValue = _passwordController.text.trim();
    Clipboard.setData(ClipboardData(text: passwordValue));
  }

  Role _roleByName(String name) {
    assert (RoleNames.containsValue(name));
    for (MapEntry<Role,String> e in RoleNames.entries) {
      if (e.value == name) {
        return e.key;
      }
    }
    return Role.ROLE_ANY;
  }

  void _pickRole() {
    var builder = (BuildContext context) {
      List<Widget> roleItems = List.empty(growable: true);
      for (MapEntry<Role,String> e in RoleNames.entries) {
        if (e.key != Role.ROLE_ANY) {
          roleItems.add(YTextButton(e.value, () {
            setState(() {
              _roleController.text = e.value;
              _checkIfCanSubmit();
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
  Widget buildCentralWidget(BuildContext context) {
    List<Widget> items = [];
    bool isAdministrator = widget.loggedUser.defaultRole==Role.ROLE_ADMINISTRATOR;
    if (!isAdministrator) {
      items.add(Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text(
          'Некоторые поля нельзя изменить.'
          ' Обратитесь к лектору курса, если обнаружите неточности.')
      ));
    }
    if (_user.id > 0) {
      items.add(_buildTextFieldItem(context, 'ID пользователя', _userIdController, _user.id.toString(), false));
    }
    items.add(_buildTextFieldItem(context, 'Фамилия', _lastNameController, _user.lastName, isAdministrator));
    items.add(_buildTextFieldItem(context, 'Имя', _firstNameController, _user.firstName, isAdministrator));
    items.add(_buildTextFieldItem(context, 'Отчество', _midNameController, _user.midName, isAdministrator));
    items.add(_buildTextFieldItem(context, 'Группа', _groupNameController, _user.groupName, isAdministrator));
    items.add(_buildTextFieldItem(context, 'EMail', _emailController, _user.email, isAdministrator));

    String passwordValue = '';
    String? passwordHint = '';
    bool passwordEditable = false;
    List<Widget> passwordActionButtons = [];
    final copyPasswordButton = TextButton(child: Text('Скопировать'), onPressed: _copyPasswordToClipboard);
    final changePasswordButton = TextButton(child: Text('Изменить'), onPressed: _changePassword);
    final resetPasswordButton = TextButton(
      child: Text('Сбросить'),
      onPressed: _resetPassword,
      style: ButtonStyle(foregroundColor: MaterialStateProperty.all(Theme.of(context).errorColor)),
    );
    if (isMyself) {
      passwordEditable = true;
      if (_user.password.isNotEmpty) {
        passwordValue = _user.password;
        passwordHint = null;
        passwordActionButtons.add(copyPasswordButton);
      } else {
        passwordValue = '';
        passwordHint = 'Не отображается, но можно изменить';
      }
      passwordActionButtons.add(changePasswordButton);
    }
    else if (isAdministrator && _user.id>0) {
      passwordEditable = false;
      if (_user.password.isNotEmpty) {
        passwordValue = _user.password;
        passwordHint = null;
        passwordActionButtons.add(copyPasswordButton);
      } else {
        passwordValue = '';
        passwordHint = 'Пароль был изменен пользователем';
      }
      passwordActionButtons.add(resetPasswordButton);
    }
    else if (_user.id == 0) {
      passwordActionButtons.add(copyPasswordButton);
      passwordValue = generateRandomPassword();
    }
    items.add(_buildTextFieldItem(context, 'Пароль', _passwordController,
        passwordValue, passwordEditable,
        hintText: passwordHint,
        actionWidgets: passwordActionButtons));

    // YTextButton? roleActionButton = null;
    String roleName = '';
    // if (isAdministrator) {
    //   roleActionButton = YTextButton('Изменить', _pickRole);
    // }
    if (_user.id == 0) {
      if (_roleController.text.trim().isNotEmpty)
        roleName = _roleController.text.trim();
      else
        roleName = RoleNames[Role.ROLE_STUDENT]!;
    }
    else {
      roleName = RoleNames[_user.defaultRole]!;
    }
    // items.add(_buildTextFieldItem(context, 'Роль по умолчанию',
    //     _roleController, roleName, false,
    //     actionWidgets: [roleActionButton!]
    // ));
    items.add(_buildDropdownFieldItem(
        context, 'Роль по умолчанию', RoleNames.values.toList().sublist(1),
        _roleController, roleName, isAdministrator,
    ));
    if (_errorString.isNotEmpty) {
      items.add(Padding(padding: EdgeInsets.all(10), child: Text(_errorString,
        style: TextStyle(color: Theme.of(context).errorColor),
      )));
    }
    if (_statusText.isNotEmpty) {
      items.add(Padding(padding: EdgeInsets.all(10), child: Text(_statusText,
        style: TextStyle(color: Theme.of(context).primaryColor),
      )));
    }
    return Column(children: items);
  }

  bool _isSubmitting = false;
  bool _canSubmit = false;

  void _submit() {
    setState(() {
      _isSubmitting = true;
    });
    User user = User();
    if (_user.id > 0) {
      user = _user;
    } 
    user.firstName = _firstNameController.text.trim();
    user.lastName = _lastNameController.text.trim();
    user.midName = _midNameController.text.trim();
    user.groupName = _groupNameController.text.trim();
    user.password = _passwordController.text.trim();
    user.email = _emailController.text.trim();
    user.defaultRole = _roleByName(_roleController.text.trim());
    user.disabled = false;
    UserManagementClient service = ConnectionController.instance!.usersService;
    service.createOrUpdateUser(user).then((changedUser) {
      setState(() {
        _user = changedUser;
        _errorString = '';
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

  void _checkIfCanSubmit() {
    bool canSubmit = false;
    bool firstNameSet = _firstNameController.text.trim().isNotEmpty;
    bool lastNameSet = _lastNameController.text.trim().isNotEmpty;
    bool passwordSet = _user.id > 0;
    if (_user.id == 0) {
      passwordSet = _passwordController.text.trim().isNotEmpty;
      canSubmit = firstNameSet && lastNameSet && passwordSet;
    }
    else {
      Role newRole = _roleByName(_roleController.text.trim());
      bool firstNameChanged = _user.firstName != _firstNameController.text.trim();
      bool lastNameChanged = _user.lastName != _lastNameController.text.trim();
      bool midNameChanged = _user.midName != _midNameController.text.trim();
      bool groupNameChanged = _user.groupName != _groupNameController.text.trim();
      bool emailChanged = _user.email != _emailController.text.trim();
      bool roleChanged = _user.defaultRole != newRole;
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