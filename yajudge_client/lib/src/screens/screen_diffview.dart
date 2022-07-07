import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:yajudge_common/yajudge_common.dart';

import '../controllers/connection_controller.dart';
import '../widgets/source_view_widget.dart';
import 'screen_base.dart';

class DiffViewScreen extends BaseScreen {

  final DiffViewRequest source;

  DiffViewScreen(this.source, {required super.loggedUser});

  @override
  State<StatefulWidget> createState() {
    String title = '';
    bool bothAreSubmissions = source.first.hasSubmission() && source.second.hasSubmission();
    if (bothAreSubmissions) {
      title = 'Сравнение посылок ${source.first.submission.id} и ${source.second.submission.id}';
    } else {
      final submission = source.first.hasSubmission()? source.first.submission : source.second.submission;
      title = 'Сравнение посылки ${submission.id} с внешним источником';
    }
    return DiffViewScreenState(title: title);
  }

}


extension StringExtension on String {
  int get newLinesCount {
    int result = 0;
    for (int i=0; i<length; i++) {
      if (codeUnitAt(i) == 10) {
        result ++;
      }
    }
    return result;
  }
}

class _FileDiffView {
  final List<DiffOperation> diffs;
  final String fileName;
  final String firstText;
  final String secondText;
  final Map<int,int> firstEmptyLines = {};
  final Map<int,int> secondEmptyLines = {};
  final Set<int> firstChangedLines = {};
  final Set<int> secondChangedLines = {};

  _FileDiffView(this.firstText,this.secondText, this.diffs, this.fileName) {
    _buildAlignment(firstText, secondText);
  }

  void _buildAlignment(String firstText, String secondText) {
    for (final diff in diffs) {
      if (diff.operation == DiffOperationType.LINE_DELETED) {
        int voidLength = diff.from.length;
        int afterLine = diff.to.end;
        secondEmptyLines[afterLine] = voidLength;
      }
      else if (diff.operation == DiffOperationType.LINE_INSERTED) {
        int voidLength = diff.to.length;
        int afterLine = diff.from.end;
        firstEmptyLines[afterLine] = voidLength;
      }
      else if (diff.operation == DiffOperationType.LINE_DIFFER) {
        int firstRangeLength = diff.from.length;
        int secondRangeLength = diff.to.length;
        if (secondRangeLength > firstRangeLength) {
          int afterLine = diff.from.end;
          int voidLength = secondRangeLength - firstRangeLength;
          firstEmptyLines[afterLine] = voidLength;
        }
        else if (firstRangeLength > secondRangeLength) {
          int afterLine = diff.to.end;
          int voidLength = firstRangeLength - secondRangeLength;
          secondEmptyLines[afterLine] = voidLength;
        }
        int diffLinesCount = min(diff.from.length, diff.to.length);
        for (int i=0; i<diffLinesCount; i++) {
          firstChangedLines.add(diff.from.start + i);
          secondChangedLines.add(diff.to.start + i);
        }
      }
    }
  }
}

class DiffViewScreenState extends BaseScreenState {

  DiffViewResponse? _data;
  List<_FileDiffView>? _fileDiffs;

  DiffViewScreenState({required super.title});

  @override
  void initState() {
    super.initState();
    _loadSubmissions();
  }

  void _loadSubmissions() {
    final service = ConnectionController.instance!.submissionsService;
    final request = (widget as DiffViewScreen).source;
    service.getSubmissionsToDiff(request).then((result) {
      if (!mounted) {
        return;
      }
      setState(() {
        _data = result;
        _buildDiffs();
      });
    });
  }

  void _buildDiffs() {
    _fileDiffs = [];
    for (final diff in _data!.diffs) {
      final fileName = diff.fileName;
      final firstText = diff.firstText;
      final secondText = diff.secondText;
      final operations = diff.operations;
      _fileDiffs!.add(_FileDiffView(firstText, secondText, operations, fileName));
    }
  }

  @override
  Widget buildCentralWidget(BuildContext context) {
    if (_data == null || _fileDiffs == null) {
      return Center(child: Text('Загрузка...'));
    }
    List<Widget> parts = [];
    parts.addAll(_buildCommonInformation(context));
    parts.addAll(_buildAllFiles(context));
    return Column(children: parts, crossAxisAlignment: CrossAxisAlignment.start,);
  }
  
  List<Widget> _buildCommonInformation(BuildContext context) {
    Padding wrapIntoPadding(Widget w, [double topPadding = 10]) {
      return Padding(
          child: w,
          padding: EdgeInsets.fromLTRB(0, topPadding, 0, 10)
      );
    }
    final theme = Theme.of(context);
    Text makeText(String text, [Color? color, bool underline = false]) {
      return Text(text,
          style: theme.textTheme.bodyText1!.merge(TextStyle(
            fontSize: 16,
            color: color,
            decoration: underline? TextDecoration.underline : null,
          ))
      );
    }
    String sourceToString(SolutionSource source) {
      if (source.hasSubmission()) {
        final submission = source.submission;
        final author = submission.user;
        final problemId = submission.problemId;
        final id = submission.id;
        return 'посылка $id задачи $problemId, автор ${author.fullName}';
      }
      else {
        final external = source.external;
        final url = external.knownUrl;
        String author = external.knownAuthor;
        if (author.isEmpty) {
          author = 'неизвестен';
        }
        return 'внешний источник $url, автор $author';
      }
    }
    Widget makeRow(String text) {
      return wrapIntoPadding(makeText(text));
    }
    final left = 'Слева: ${sourceToString(_data!.request.first)}';
    final right = 'Справа: ${sourceToString(_data!.request.second)}';

    return [
      makeRow(left),
      makeRow(right),
    ];
  }

  List<Widget> _buildAllFiles(BuildContext context) {
    final result = <Widget>[];
    for (final file in _fileDiffs!) {
      result.addAll(_buildFile(context, file));
    }
    return result;
  }

  List<Widget> _buildFile(BuildContext context, _FileDiffView file) {
    final theme = Theme.of(context);
    final fileHeadStyle = theme.textTheme.headline6;
    final fileHeadPadding = EdgeInsets.fromLTRB(8, 10, 8, 4);
    final result = <Widget>[];
    result.add(
      Container(
        padding: fileHeadPadding,
        child: Text('Файл ${file.fileName}:', style: fileHeadStyle)
      )
    );
    result.add(Row(
      children: [
        _createFilePreview(context, file.fileName, file.firstText, file.firstEmptyLines, file.firstChangedLines),
        _createFilePreview(context, file.fileName, file.secondText, file.secondEmptyLines, file.secondChangedLines),
      ],
      crossAxisAlignment: CrossAxisAlignment.start,
    ));
    return result;
  }

  Widget _createFilePreview(BuildContext context, String fileName, String content, Map<int,int> emptyLines, Set<int> changedLines) {
    final fullWidth = MediaQuery.of(context).size.width;
    final actualWidth = fullWidth - 48; // left/right padding and space between
    final sourceWidth = actualWidth / 2;
    final sourceView = SourceViewWidget(
      text: content,
      fileName: fileName,
      withLineNumbers: true,
      lineCommentController: null,
      maxWidth: sourceWidth,
      emptyLines: emptyLines,
      changedLines: changedLines,
    );
    return Container(
      child: sourceView,
      constraints: BoxConstraints(
        maxWidth: sourceWidth,
      ),
    );
  }

}