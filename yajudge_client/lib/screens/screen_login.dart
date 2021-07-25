import 'package:flutter/cupertino.dart';
import '../../utils/utils.dart';

import '../app.dart';
import '../wsapi/connection.dart';
import '../wsapi/users.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class LoginScreen extends StatefulWidget {
  LoginScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return new LoginScreenState();
  }
}

class LoginScreenState extends State<LoginScreen> {
  UsersService _service;
  RegExp _emailRegExp = new RegExp(
    r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*$',
    multiLine: false,
  );
  RegExp _idRegExp = new RegExp(r'^[0-9]+$', multiLine: false);
  final _formKey = GlobalKey<FormState>();

  User _candidate = User();

  User? _loggedUser;
  Session? _loggedSession;
  String? _errorText;
  bool _buttonDisabled = false;

  LoginScreenState()
      : _service = UsersService.instance,
        super();

  void setError(Object errorObj) {
    if (errorObj.runtimeType == ResponseError) {
      ResponseError error = errorObj as ResponseError;
      _errorText = error.message;
      if (_errorText!.isNotEmpty) {
        _errorText = _errorText![0].toUpperCase() + _errorText!.substring(1);
      }
      if (error.code != 0 && error.code != 99999) {
        _errorText = _errorText! + " (код " + error.code.toString() + ")";
      }
    }
    else {
      _errorText = errorObj.toString();
    }
  }

  void processLogin() {
    _service.authorize(_candidate).then((Session session) {
      AppState.instance.sessionId = session.cookie;
      Navigator.pushReplacementNamed(context, '/');
    }).catchError((Object error) {
      setState(() {
        _loggedUser = null;
        _loggedSession = null;
        _buttonDisabled = false;
        setError(error);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    String greetingMessage =
        'Для продолжения работы необходимо войти с использованием '
        'целочисленного ID пользователя или EMail при регистрации.'
    ;
    Text greetingItem = Text(greetingMessage, textAlign: TextAlign.center);
    String? Function(String? value) loginValidator = (String? value) {
      if (value == null || value.isEmpty) {
        return 'Необходимо указать ID или EMail';
      }
      if (!_emailRegExp.hasMatch(value) &&
          !_idRegExp.hasMatch(value)) {
        return 'Неправильный формат ID или EMail';
      }
    };
    void Function(String? value) loginSaver = (String? value) {
      if (_emailRegExp.hasMatch(value!)) {
        _candidate.email = value;
        _candidate.id = 0;
      } else if (_idRegExp.hasMatch(value)) {
        _candidate.id = int.parse(value);
        _candidate.email = '';
      }
    };
    String? Function(String? value) passwordValidator = (String? value) {
      if (value == null || value.isEmpty) {
        return 'Пароль не бывает пустым';
      }
    };
    void Function(String? value) passwordSaver = (String? value) {
      _candidate.password = value!;
    };
    Widget errorItem = Padding(
      padding: EdgeInsets.all(10),
      child: Text(_errorText != null ? 'Ошибка авторизации: $_errorText' : '',
        style: TextStyle(color: Theme.of(context).errorColor),
      ),
    );
    void Function() buttonHandler = () {
      if (_formKey.currentState!.validate()) {
        setState(() {
          _errorText = null;
          _formKey.currentState!.save();
          // _buttonDisabled = true;
        });
        processLogin();
      }
    };
    String loginLabel = 'Логин';
    String passwordLabel = 'Пароль';
    String loginHint = 'ID пользователя или EMail';
    String passwordHint = 'Пароль';
    String buttonText = 'Войти';
    Widget loginField, passwordField, loginButton;
    Form form;
    loginField = TextFormField(
      decoration: InputDecoration(hintText: loginHint),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: loginValidator,
      onSaved: loginSaver,
    );
    passwordField = TextFormField(
      obscureText: true,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(hintText: passwordHint),
      validator: passwordValidator,
      onSaved: passwordSaver,
    );
    loginButton = TextButton(
      child: Text(buttonText.toUpperCase()),
      onPressed: _buttonDisabled ? null : buttonHandler,
    );
    form = Form(
        key: _formKey,
        child: Column(children: [loginField, passwordField, errorItem,])
    );
    return Column(children: [
      greetingItem,
      const SizedBox(height: 8,),
      Card(child: Container(
        constraints: BoxConstraints.tightFor(width: 500),
        padding: EdgeInsets.all(10),
        child: Column(
          children: [
            form,
            Row(children: [loginButton], mainAxisAlignment: MainAxisAlignment.end)
          ],
        ),
      )),
    ]);
  }
}
