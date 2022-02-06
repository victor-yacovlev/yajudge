import 'package:flutter/widgets.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'screen_base.dart';

class LoadingScreen extends BaseScreen {
  final String title;
  final String message;

  LoadingScreen([this.title='', this.message='']): super(loggedUser: User(), allowUnauthorized: true);

  @override
  State<StatefulWidget> createState() => LoadingScreenState(title);
}

class LoadingScreenState extends BaseScreenState {
  LoadingScreenState(String title): super(title: title);

  @override
  Widget buildCentralWidget(BuildContext context) {
    return Center(
      child: Text((widget as LoadingScreen).message),
    );
  }
}