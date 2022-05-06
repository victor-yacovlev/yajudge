import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import '../client_app.dart';
import '../controllers/connection_controller.dart';
import 'package:yajudge_common/yajudge_common.dart';

import 'package:flutter/material.dart';

import '../utils/utils.dart';

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
  Uri _serverUri = Uri();

  String? _errorText;
  bool _buttonDisabled = false;

  LoginScreenState() : super();

  final logger = Logger('LoginScreen');

  late FocusNode _loginFocusNode;
  late FocusNode _passwordFocusNode;

  @override
  void initState() {
    super.initState();
    _loginFocusNode = FocusNode();
    _passwordFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _loginFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void setError(Object errorObj) {
    _errorText = errorObj.toString();
  }

  void processLogin() {
    if (_serverUri.host.isEmpty) {
      logger.info('Server URI not set, using default base: ${Uri.base}');
      _serverUri = Uri.base;
    }
    PlatformsUtils.getInstance().saveSettingsValue('api_url', _serverUri.toString());
    ConnectionController.initialize(_serverUri);
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
      final url = ConnectionController.instance!.connectionUri;
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
    final greetingMessage =
        'Для продолжения работы необходимо войти в систему'
    ;
    final serverValidator = (String? value) {
      if (value == null || value.trim().isEmpty) {
        return 'Необходимо указать сервер для подключения';
      }
      if (null == Uri.tryParse(value)) {
        return 'Некорректный адрес сервера';
      }
    };
    final serverSaver = (String? value) {
      _serverUri = Uri.parse(value!);
    };
    final loginValidator = (String? value) {
      if (value == null || value.trim().isEmpty) {
        return 'Необходимо указать ID, логин или EMail';
      }
    };
    final loginSaver = (String? value) {
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
    final passwordValidator = (String? value) {
      if (value == null || value.trim().isEmpty) {
        return 'Пароль не бывает пустым';
      }
    };
    final passwordSaver = (String? value) {
      _candidate.password = value!;
    };
    Widget errorItem = Padding(
      padding: EdgeInsets.all(10),
      child: Text(_errorText != null ? 'Ошибка авторизации: $_errorText' : '',
        style: TextStyle(color: Theme.of(context).errorColor),
      ),
    );
    final buttonHandler = () {
      if (_formKey.currentState!.validate()) {
        setState(() {
          _errorText = null;
          _formKey.currentState!.save();
          // _buttonDisabled = true;
        });
        processLogin();
      }
    };
    final serverHint = 'Сервер для подключения';
    final loginHint = 'ID пользователя или EMail';
    final passwordHint = 'Пароль';
    final buttonText = 'Войти';
    Widget? serverField;
    Widget loginField;
    Widget passwordField;
    Widget loginButton;
    Form form;
    List<Widget> formItems = [];

    String initialServerValue = '';
    if (ConnectionController.instance != null) {
      initialServerValue = ConnectionController.instance!.connectionUri.toString();
    }
    bool showServerField = true;
    if (kIsWeb) {
      if (initialServerValue.isEmpty) {
        initialServerValue = Uri.base.scheme + '://' + Uri.base.host;
        if (Uri.base.host == 'localhost') {
          initialServerValue += ":9095";
        }
      }
      if (Uri.base.host != 'localhost') {
        showServerField = false;
      }
    }
    if (showServerField) {
      serverField = TextFormField(
        autofocus: true,
        initialValue: initialServerValue.isEmpty ? null : initialServerValue,
        decoration: InputDecoration(hintText: serverHint),
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: serverValidator,
        onSaved: serverSaver,
        onEditingComplete: () { _loginFocusNode.requestFocus(); },
      );
      formItems.add(serverField);
    }

    loginField = TextFormField(
      autofocus: serverField==null,
      focusNode: _loginFocusNode,
      decoration: InputDecoration(hintText: loginHint),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: loginValidator,
      onSaved: loginSaver,
      autofillHints: [AutofillHints.name],
      onEditingComplete: () { _passwordFocusNode.requestFocus(); },
    );
    formItems.add(loginField);

    passwordField = TextFormField(
      obscureText: true,
      focusNode: _passwordFocusNode,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(hintText: passwordHint),
      validator: passwordValidator,
      onSaved: passwordSaver,
      autofillHints: [AutofillHints.password],
      onEditingComplete: () { buttonHandler(); },
    );
    formItems.add(passwordField);

    loginButton = TextButton(
      child: Text(buttonText.toUpperCase()),
      onPressed: _buttonDisabled ? null : buttonHandler,
    );

    formItems.add(errorItem);
    form = Form(
        key: _formKey,
        child: Column(children: formItems)
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
