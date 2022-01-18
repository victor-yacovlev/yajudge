import 'package:fixnum/fixnum.dart';
import 'package:yajudge_common/yajudge_common.dart';

import '../client_app.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  LoginScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return new LoginScreenState();
  }
}

class LoginScreenState extends State<LoginScreen> {
  UserManagementClient _service = AppState.instance.usersService;
  RegExp _emailRegExp = new RegExp(
    r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*$',
    multiLine: false,
  );
  RegExp _idRegExp = new RegExp(r'^[0-9]+$', multiLine: false);
  final _formKey = GlobalKey<FormState>();

  User _candidate = User();

  String? _errorText;
  bool _buttonDisabled = false;

  LoginScreenState()
      : _service = AppState.instance.usersService,
        super();

  void setError(Object errorObj) {
    _errorText = errorObj.toString();
  }

  void processLogin() {
    _service.authorize(_candidate).then((Session session) {
      AppState.instance.session = session;
      Future.delayed(Duration(seconds: 2)).then((value) {
        Navigator.pushReplacementNamed(context, AppState.instance.initialRoute);
      });
    }).catchError((Object error) {
      setState(() {
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
        _candidate.id = Int64(0);
      } else if (_idRegExp.hasMatch(value)) {
        _candidate.id = Int64.parseInt(value);
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
      onPressed: _buttonDisabled || AppState.instance.session!=null ? null : buttonHandler,
    );
    form = Form(
        key: _formKey,
        child: Column(children: [loginField, passwordField, errorItem,])
    );
    return Column(children: [
      // greetingItem,
      // const SizedBox(height: 8,),
      Card(child: Container(
        constraints: BoxConstraints.tightFor(width: 500),
        padding: EdgeInsets.all(10),
        child: Column(
          children: [
            Text(greetingMessage),
            form,
            Row(children: [loginButton], mainAxisAlignment: MainAxisAlignment.end)
          ],
        ),
      )),
    ]);
  }
}
