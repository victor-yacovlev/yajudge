import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:yajudge_client/screens/screen_base.dart';
import 'package:yajudge_client/widgets/rich_text_viewer.dart';
import 'package:yajudge_client/wsapi/courses.dart';

import '../app.dart';

class CourseReadingScreen extends BaseScreen {
  final String courseId;
  final String readingKey;
  final TextReading? reading;

  CourseReadingScreen(this.courseId, this.readingKey, this.reading) : super();

  @override
  State<StatefulWidget> createState() {
    return CourseReadingScreenState();
  }

}

class CourseReadingScreenState extends BaseScreenState {
  late CourseReadingScreen screen;

  TextReading? _reading;
  String? _errorString;

  CourseReadingScreenState() : super(title: '') ;

  void _loadCourseData() {
    AppState.instance.loadCourseData(screen.courseId)
        .then((value) => setState(() {
          CourseData courseData = value;
          _reading = courseData.findReadingByKey(screen.readingKey);
          if (_reading == null) {
            _errorString = 'Ридинг [' + screen.readingKey + '] не найден';
          }
          this.title = _reading!.title;
        }))
        .onError((err, stackTrace) => setState(() {
          _errorString = err.toString();
        }));
  }

  @override
  void initState() {
    super.initState();
    screen = widget as CourseReadingScreen;
    if (screen.reading != null) {
      setState(() {
        this.title = screen.reading!.title;
        this._reading = screen.reading!;
      });
    } else {
      _loadCourseData();
    }
  }

  @override
  Widget buildCentralWidget(BuildContext context) {
    late Widget childToPlace;
    if (_reading != null) {
      TextTheme theme = Theme.of(context).textTheme;
      childToPlace = RichTextViewer(
          _reading!.data,
          _reading!.contentType,
          theme: theme
      );
    } else if (_errorString != null) {
      childToPlace = Text(_errorString!, style: TextStyle(color: Theme.of(context).errorColor));
    } else {
      childToPlace = Text('Загружается...');
    }
    Container container = Container(
      padding: EdgeInsets.fromLTRB(0, 10, 0, 100),
      constraints: BoxConstraints(
        minWidth: 400,
        minHeight: 600,
      ),
      child: childToPlace,
    );
    return container;
  }

}