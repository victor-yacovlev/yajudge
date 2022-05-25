import 'package:flutter/material.dart';
import 'screen_base.dart';
import '../widgets/rich_text_viewer.dart';
import 'package:yajudge_common/yajudge_common.dart';

class CourseReadingScreen extends BaseScreen {
  final TextReading textReading;

  CourseReadingScreen({
    required User user,
    required this.textReading,
  }) : super(loggedUser: user);

  @override
  State<StatefulWidget> createState() {
    return CourseReadingScreenState(this);
  }

}

class CourseReadingScreenState extends BaseScreenState {

  final CourseReadingScreen screen;

  CourseReadingScreenState(this.screen) : super(title: screen.textReading.title) ;

  @override
  Widget buildCentralWidget(BuildContext context) {
    TextReading textReading = (widget as CourseReadingScreen).textReading;
    TextTheme theme = Theme.of(context).textTheme;
    Widget viewer = RichTextViewer(textReading.data, textReading.contentType,
        theme: theme, resources:
        textReading.resources
    );

    double screenWidth = MediaQuery.of(context).size.width;
    double horizontalMargins = (screenWidth - 950) / 2;
    if (horizontalMargins < 0) {
      horizontalMargins = 0;
    }
    Container outerBox = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      margin: EdgeInsets.fromLTRB(horizontalMargins, 20, horizontalMargins, 20),
      padding: EdgeInsets.fromLTRB(20, 0, 20, 50),
      constraints: BoxConstraints(
        minWidth: 400,
        minHeight: 600,
      ),
      child: viewer,
    );
    return outerBox;
  }

}