import 'package:flutter/material.dart';
import 'screen_base.dart';
import '../widgets/rich_text_viewer.dart';
import 'package:yajudge_common/yajudge_common.dart';

import '../client_app.dart';

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
          _reading = findReadingByKey(courseData, screen.readingKey);
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
      child: childToPlace,
    );
    return outerBox;
  }

}