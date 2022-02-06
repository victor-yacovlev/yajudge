import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:yajudge_common/yajudge_common.dart';
import '../widgets/unified_widgets.dart';
import 'screen_base.dart';

class ErrorScreen extends BaseScreen {
  final String title;
  final String message;

  ErrorScreen(this.title, this.message): super(loggedUser: User(), allowUnauthorized: true);

  @override
  State<StatefulWidget> createState() => ErrorScreenState();
}

class ErrorScreenState extends BaseScreenState {
  ErrorScreenState(): super(title: 'Ошибка');

  @override
  Widget buildCentralWidget(BuildContext context) {
    final title = (widget as ErrorScreen).title;
    final message = (widget as ErrorScreen).message;
    return Center(
        child: Container(
            margin: EdgeInsets.all(50),
            padding: EdgeInsets.all(20),
            constraints: BoxConstraints(
              minWidth: 400,
              maxHeight: 400,
            ),
            decoration: BoxDecoration(
              border:
              Border.all(color: Theme.of(context).errorColor, width: 2.0),
            ),
            child:
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(title, style: Theme.of(context).textTheme.headline5),
              Padding(
                child: Text(message, style: Theme.of(context).textTheme.bodyText1),
                padding: EdgeInsets.all(20)
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  YTextButton('Назад', () {
                    Navigator.pop(context);
                  }, color: Theme.of(context).errorColor),
                  YTextButton('Перезагрузить', () {
                    final path = ModalRoute.of(context)!.settings.name!;
                    Navigator.pushReplacementNamed(context, path);
                  }, color: Theme.of(context).errorColor),
                ],
              ),
            ])));
  }
}