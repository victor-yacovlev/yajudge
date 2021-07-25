import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:yajudge_client/screens/screen_base.dart';
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
  String? _markdownPreprocessed;

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
          if (_reading!.contentType == 'text/markdown') {
            _markdownPreprocessed = removeMarkdownHeading(_reading!.data);
          }
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
        if (_reading!.contentType == 'text/markdown') {
          _markdownPreprocessed = removeMarkdownHeading(_reading!.data);
        }
      });
    } else {
      _loadCourseData();
    }
  }

  String removeMarkdownHeading(String src) {
    List<String> lines = src.split('\n');
    String result = '';
    for (String line in lines) {
      if (line.trim().startsWith('#') && !line.trim().startsWith('##')) {
        // skip heading
      } else {
        result += line + '\n';
      }
    }
    return result;
  }

  Widget _createMarkdown(BuildContext context) {
    return MarkdownBody(
      // TODO make greater look
      styleSheet: MarkdownStyleSheet(textScaleFactor: 1.2),
      selectable: false,
      data: _markdownPreprocessed!,
      extensionSet: md.ExtensionSet(
          md.ExtensionSet.gitHubFlavored.blockSyntaxes,
          [md.EmojiSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
      ),
    );
  }

  Widget _createViewFromReadingData(BuildContext context) {
    if (_reading!.contentType == 'text/markdown') {
      return _createMarkdown(context);
    }
    else if (_reading!.contentType.startsWith('text/')) {
      return Text(_reading!.data);
    } else {
      return Text('Не могу отобразить ' + _reading!.contentType,
        style: TextStyle(color: Theme.of(context).errorColor)
      );
    }
  }

  @override
  Widget buildCentralWidgetCupertino(BuildContext context) {
    late Widget childToPlace;
    if (_reading != null) {
      childToPlace = _createViewFromReadingData(context);
    } else if (_errorString != null) {
      childToPlace = Text(_errorString!, style: TextStyle(color: Theme.of(context).errorColor));
    } else {
      childToPlace = Text('Загружается...');
    }
    Container container = Container(
      padding: EdgeInsets.fromLTRB(20, 30, 20, 30),
      constraints: BoxConstraints(
        minWidth: 400,
        minHeight: 600,
      ),
      child: childToPlace,
    );
    return container;
  }

  @override
  Widget buildCentralWidget(BuildContext context) {
    return buildCentralWidgetCupertino(context);
  }

}