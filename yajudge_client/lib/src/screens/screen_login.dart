import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import '../client_app.dart';
import '../controllers/connection_controller.dart';
import 'package:yajudge_common/yajudge_common.dart';

import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {

  final AppState appState;

  LoginScreen({required this.appState, Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return new LoginScreenState();
  }
}

class LoginScreenState extends State<LoginScreen> {

  RegExp _emailRegExp = new RegExp(
    r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*$',
    multiLine: false,
  );
  RegExp _idRegExp = new RegExp(r'^[0-9]+$', multiLine: false);
  final _formKey = GlobalKey<FormState>();

  User _candidate = User();

  String? _errorText;
  bool _buttonDisabled = false;

  LoginScreenState() : super();

  final logger = Logger('LoginScreen');

  void setError(Object errorObj) {
    _errorText = errorObj.toString();
  }

  void processLogin() {
    ConnectionController.instance!.usersService.authorize(_candidate).then((Session session) {
      logger.info('logger user ${session.user}');
      ConnectionController.instance!.setSession(session);
      setState(() {
        String initialRoute = session.user.initialRoute;
        if (initialRoute.isEmpty) {
          initialRoute = '/';
        }
        Navigator.pushReplacementNamed(context, initialRoute);
      });
    }).catchError((Object error) {
      logger.warning('cant login user: $error}');
      setState(() {
        _buttonDisabled = false;
        if (error is GrpcError) {
          setLoginErrorText(error);
        }
        else {
          setError(error);
        }
      });
    });
  }

  void setLoginErrorText(GrpcError error) {
    int code = error.code;
    if (code == StatusCode.unavailable) {
      final url = ConnectionController.instance!.serverApiUrl;
      setError('сервер ${url} не доступен');
    }
    else if (code == StatusCode.notFound) {
      setError('такой пользователь не существует');
    }
    else if (code == StatusCode.permissionDenied) {
      setError('неверный пароль или пользователь заблокирован');
    }
  }

  @override
  Widget build(BuildContext context) {
    String greetingMessage =
        'Для продолжения работы необходимо войти в систему'
    ;
    String? Function(String? value) loginValidator = (String? value) {
      if (value == null || value.isEmpty) {
        return 'Необходимо указать ID или EMail';
      }
    };
    void Function(String? value) loginSaver = (String? value) {
      if (_emailRegExp.hasMatch(value!)) {
        _candidate.email = value;
        _candidate.id = Int64(0);
        _candidate.login = '';
      } else if (_idRegExp.hasMatch(value)) {
        _candidate.id = Int64.parseInt(value);
        _candidate.email = '';
      } else if (value.trim().isNotEmpty) {
        _candidate.login = value.trim();
        _candidate.email = '';
        _candidate.id = Int64(0);
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
