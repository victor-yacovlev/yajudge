import 'dart:math';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:protobuf/protobuf.dart';
import 'package:yajudge_common/yajudge_common.dart';

const maxWidgetWidth = 950;
const borderColor = Colors.black12;
const lineColor = Color.fromARGB(255, 240, 240, 255);
const highlightBackground = Color.fromARGB(255, 250, 250, 255);
const commentBackground = Color.fromARGB(255, 255, 230, 230);
const commentLeftMargin = 8.0;
const commentTextColor = Colors.red;
const tabExpand = '    ';
const leadingSpacesMarkColor = Colors.black12;

class LineCommentController {
  final bool editable;
  final log = Logger('LineCommentController');
  final List<LineComment> _comments = [];
  LineCommentController({required this.editable});
  final List<void Function()> _changeListeners = [];

  void addListener(void Function() listener) {
    _changeListeners.add(listener);
  }

  List<LineComment> get comments => _comments;

  set comments(Iterable<LineComment> newComments) {
    _comments.clear();
    for (final entry in newComments) {
      _comments.add(entry.deepCopy());
    }
  }

  void notify() {
    final commentTexts = comments.map((e) => e.message);
    log.info('changed line comments, have ${comments.length} lines now: $commentTexts');
    for (final listener in _changeListeners) {
      listener();
    }
  }
}

class SourceViewWidget extends StatefulWidget {
  final String text;
  late final List<String> lines;
  final bool withLineNumbers;
  final LineCommentController? lineCommentController;
  final String fileName;
  SourceViewWidget({
    required this.text,
    required this.fileName,
    this.withLineNumbers = false,
    required this.lineCommentController,
    Key? key
  }): super(key: key) {
    lines = text.split('\n');
  }

  @override
  State<StatefulWidget> createState() => SourceViewWidgetState();

  int get linesCount {
    return lines.length;
  }

  int get maxLineLength {
    int result = 0;
    for (final line in lines) {
      if (line.length > result) {
        result = line.length;
      }
    }
    return result;
  }
}

class LineCommentableTextPainter extends CustomPainter {
  final TextStyle mainStyle;
  final TextStyle commentStyle;
  final SourceViewWidgetState state;

  LineCommentableTextPainter(this.state, this.mainStyle, this.commentStyle);

  @override
  void paint(Canvas canvas, Size size) {
    final lines = state.widget.lines;
    final comments = state.widget.lineCommentController?.comments;
    final lineHeight = calculateLineHeight(mainStyle);
    final commentHeight = calculateLineHeight(commentStyle);
    final commentInLineOffset = (lineHeight - commentHeight) / 2.0;
    final linePaint = Paint()..color = lineColor;
    final whiteSpaceMarkPaint = Paint()
      ..color = leadingSpacesMarkColor
      ..strokeWidth = 2.0
      ;
    final hoverPaint = Paint()..color = highlightBackground;
    final commentPaint = Paint()..color = commentBackground;
    Offset offset = Offset(0, 0);
    for (int i=0; i<lines.length; i++) {
      LineComment? comment;
      if (comments != null) {
        for (final candidate in comments) {
          if (candidate.lineNumber == i) {
            comment = candidate;
            break;
          }
        }
      }
      final lineRect = Rect.fromLTRB(0, offset.dy, size.width, offset.dy+lineHeight);
      if (comment != null) {
        canvas.drawRect(lineRect, commentPaint);
      }
      else if (state._currentHoveredLine == i) {
        canvas.drawRect(lineRect, hoverPaint);
      }
      final line = lines[i];
      final mainSpan = TextSpan(text: line.replaceAll('\t', tabExpand), style: mainStyle);
      final mainPainter = TextPainter(text: mainSpan, textDirection: TextDirection.ltr);
      mainPainter.layout();
      mainPainter.paint(canvas, offset);
      drawWhiteSpaceMarkers(canvas, whiteSpaceMarkPaint, mainStyle, offset, line);
      if (comment != null && state._currentCommentEditingLine!=comment.lineNumber) {
        final mainMetrics = mainPainter.computeLineMetrics();
        double dx = 0.0;
        if (mainMetrics.isNotEmpty) {
          dx += commentLeftMargin;
          dx += mainMetrics.first.width;
        }
        final commentSpan = TextSpan(text: comment.message, style: commentStyle);
        final commentPainter = TextPainter(text: commentSpan, textDirection: TextDirection.ltr);
        commentPainter.layout();
        commentPainter.paint(canvas, offset.translate(dx, commentInLineOffset));
      }
      offset = offset.translate(0, lineHeight);
      canvas.drawLine(Offset(0, offset.dy), Offset(size.width, offset.dy), linePaint);
    }
  }

  void drawWhiteSpaceMarkers(Canvas canvas, Paint painter, TextStyle style, Offset offset, String sourceText) {
    final lineHeight = calculateLineHeight(style);
    final charWidth = calculateLineWidth('H', style);
    final dotCenter = Offset(charWidth/2-1, lineHeight/2+1);
    final lineStart = Offset(2, lineHeight/2+1);
    final lineEnd = Offset(charWidth*tabExpand.length - 4, lineStart.dy);
    for (int i=0; i<sourceText.length; i++) {
      final currentChar = sourceText[i];
      if (currentChar != ' ' && currentChar != '\t') {
        break;
      }
      if (currentChar == ' ') {
        // draw centered dot
        canvas.drawCircle(offset.translate(dotCenter.dx, dotCenter.dy), 1.5, painter);
        offset = offset.translate(charWidth, 0);
      }
      else if (currentChar == '\t') {
        // draw tab arrow
        canvas.drawLine(
          offset.translate(lineStart.dx, lineStart.dy),
          offset.translate(lineEnd.dx, lineEnd.dy),
          painter,
        );
        canvas.drawLine(
          offset.translate(lineStart.dx, 8),
          offset.translate(lineStart.dx, lineHeight-6),
          painter,
        );
        canvas.drawLine(
          offset.translate(lineEnd.dx-8, 9),
          offset.translate(lineEnd.dx, lineEnd.dy),
          painter,
        );
        canvas.drawLine(
          offset.translate(lineEnd.dx-8, lineEnd.dy+4),
          offset.translate(lineEnd.dx, lineEnd.dy),
          painter,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }

  static Size calculateTextSize(
      List<String> lines,
      List<LineComment> comments,
      TextStyle mainStyle,
      TextStyle commentStyle,
      ) {
    double maxLineWidth = 0;
    for (int i=0; i<lines.length; i++) {
      final line = lines[i];
      double lineWidth = calculateLineWidth(line, mainStyle);

      LineComment? thisLineComment;
      for (final candidate in comments) {
        if (candidate.lineNumber == i) {
          thisLineComment = candidate;
          break;
        }
      }
      if (thisLineComment != null && thisLineComment.message.trim().isNotEmpty) {
        final commentTextSpan = TextSpan(text: thisLineComment.message.replaceAll('\n', ' '), style: commentStyle);
        final commentTextPainter = TextPainter(text: commentTextSpan, textDirection: TextDirection.ltr);
        commentTextPainter.layout();
        final commentMetrics = commentTextPainter.computeLineMetrics();
        if (commentMetrics.isNotEmpty) {
          lineWidth += commentLeftMargin;
          final metric = commentMetrics.first;
          lineWidth += metric.width;
        }
      }
      maxLineWidth = max(maxLineWidth, lineWidth);
    }
    
    return Size(maxLineWidth, calculateLineHeight(mainStyle) * lines.length);
  }
  
  static double calculateLineHeight(TextStyle style) {
    final span = TextSpan(text: 'Ap', style: style);
    final painter = TextPainter(text: span, textDirection: TextDirection.ltr);
    painter.layout();
    final metric = painter.computeLineMetrics().single;
    final top = metric.baseline - metric.ascent;
    final bottom = metric.baseline + metric.descent;
    final height = bottom - top;
    if (style.height == null) {
      return height;
    }
    else {
      return height * style.height!;
    }
  }
  
  static double calculateLineDescent(TextStyle style) {
    final span = TextSpan(text: 'Ap', style: style);
    final painter = TextPainter(text: span, textDirection: TextDirection.ltr);
    painter.layout();
    final metric = painter.computeLineMetrics().single;
    return metric.descent;
  }

  static double calculateLineWidth(String text, TextStyle style) {
    final textSpan = TextSpan(text: text.replaceAll('\t', tabExpand), style: style);
    final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
    textPainter.layout();
    final metrics = textPainter.computeLineMetrics();
    double lineWidth = 0;
    if (metrics.isNotEmpty) {
      final metric = metrics.first;
      lineWidth = metric.width;
    }
    return lineWidth;
  }
  
}

class LineNumbersPainter extends CustomPainter {
  final int linesCount;
  final TextStyle textStyle;

  LineNumbersPainter(this.linesCount, this.textStyle);

  @override
  void paint(Canvas canvas, Size size) {
    final lineHeight = LineCommentableTextPainter.calculateLineHeight(textStyle);
    final linePaint = Paint()..color = lineColor;
    Offset offset = Offset(0, 0);
    for (int i=0; i<linesCount; i++) {
      final line = '${i+1}';
      final mainSpan = TextSpan(text: line, style: textStyle);
      final mainPainter = TextPainter(text: mainSpan, textDirection: TextDirection.ltr);
      mainPainter.layout();
      final metric = mainPainter.computeLineMetrics().first;
      final textWidth = metric.width;
      final xOffset = size.width - textWidth;
      offset = offset.translate(xOffset, 0);
      mainPainter.paint(canvas, offset);
      offset = offset.translate(-xOffset, lineHeight);
      canvas.drawLine(Offset(0, offset.dy), Offset(size.width, offset.dy), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }

}

class SourceViewWidgetState extends State<SourceViewWidget> {

  final log = Logger('SourceViewWidgetState');
  int _currentHoveredLine = -1;
  int _currentCommentEditingLine = -1;
  TextEditingController? _commentEditor;

  TextStyle createTextStyle(BuildContext context) {
    final theme = Theme.of(context);
    final codeTextStyle = theme.textTheme.bodyText1!
        .merge(TextStyle(fontFamily: 'PT Mono'))
        .merge(TextStyle(letterSpacing: 1.1))
        .merge(TextStyle(height: 1.5))
        .merge(TextStyle(color: Colors.black))
    ;
    return codeTextStyle;
  }

  TextStyle createCommentStyle(BuildContext context) {
    final theme = Theme.of(context);
    final codeTextStyle = theme.textTheme.bodyText1!
        .merge(TextStyle(fontFamily: 'PT Sans'))
        .merge(TextStyle(fontStyle: FontStyle.italic))
        .merge(TextStyle(color: theme.errorColor));
    return codeTextStyle;
  }

  Widget buildEditorView(BuildContext context) {
    final controller = widget.lineCommentController;
    final canEditComments = controller==null? false : controller.editable;
    final lines = widget.lines;
    final comments = controller==null? <LineComment>[] : widget.lineCommentController!.comments;
    final mainStyle = createTextStyle(context);
    final commentStyle = createCommentStyle(context);

    final painter = LineCommentableTextPainter(this, mainStyle, commentStyle);
    Size size = LineCommentableTextPainter.calculateTextSize(lines, comments, mainStyle, commentStyle);
    final width = mainContentWidth(context) - 20;
    if (width > size.width) {
      size = Size(width, size.height);
    }
    final paintArea = CustomPaint(painter: painter, size: size);
    GestureTapCallback? clickHandler;
    MouseCursor mouseCursor = SystemMouseCursors.basic;
    if (canEditComments) {
      mouseCursor = _currentCommentEditingLine==-1 ? SystemMouseCursors.click : SystemMouseCursors.basic;
      clickHandler = _handleLineClicked;
    }
    final gestureDetector = GestureDetector(child: paintArea, onTap: clickHandler);
    final lineHeight = LineCommentableTextPainter.calculateLineHeight(mainStyle);

    final mouseArea = MouseRegion(
      child: gestureDetector,
      cursor: mouseCursor,
      onHover: (event) {
        setState((){
          final y = event.localPosition.dy;
          _currentHoveredLine = y ~/ lineHeight;
        });
      },
      onExit: (event) {
        setState((){
          _currentHoveredLine = -1;
        });
      },
    );
    if (_commentEditor == null || _currentCommentEditingLine<0 || _currentCommentEditingLine>=widget.linesCount) {
      return mouseArea;
    }
    final textField = TextField(
      style: commentStyle,
      controller: _commentEditor,
      autofocus: true,
      cursorColor: commentTextColor,
      decoration: InputDecoration(
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.black12, width: 1)
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: commentTextColor, width: 1),
        ),
      ),
      onEditingComplete: _saveComment,
    );
    double y = lineHeight * _currentCommentEditingLine - 7;
    final mainTextLine = widget.lines[_currentCommentEditingLine];
    double x = LineCommentableTextPainter.calculateLineWidth(mainTextLine, mainStyle);
    x += commentLeftMargin;
    const minWidth = 150.0;
    final editorWidth = max(minWidth, size.width - x);
    final stack = Stack(children: [
      mouseArea,
      Positioned(child: textField, left: x, top: y, height: lineHeight, width: editorWidth),
    ]);
    return stack;
  }

  void _handleLineClicked() {
    if (_currentHoveredLine == -1 || _currentHoveredLine >= widget.linesCount) {
      return;
    }
    final controller = widget.lineCommentController;
    controller?.notify();
    int editLine = _currentHoveredLine;
    if (_currentCommentEditingLine!=-1 && _currentCommentEditingLine!=editLine) {
      if (_commentEditor != null) {
        _saveComment();
      }
    } else {
      setState(() {
        _currentCommentEditingLine = editLine;
        _commentEditor = TextEditingController();
        final comments = controller==null? <LineComment>[] : controller.comments;
        for (final comment in comments) {
          if (comment.lineNumber == editLine) {
            _commentEditor!.text = comment.message;
            _commentEditor!.selection = TextSelection(baseOffset: 0, extentOffset: comment.message.length);
          }
        }
      });
    }
  }

  void _saveComment() {
    log.info('save comment');
    if (_commentEditor == null) {
      log.info('comment editor is null');
      return;
    }
    final controller = widget.lineCommentController;
    final comments = controller==null? <LineComment>[] : controller.comments;
    final fileName = widget.fileName;
    setState(() {
      int index = -1;
      final commentText = _commentEditor!.text.trim().replaceAll('\n', ' ');
      log.info('comment text is $commentText');
      for (int i=0; i<comments.length; i++) {
        if (comments[i].lineNumber == _currentCommentEditingLine && comments[i].fileName == fileName) {
          index = i;
          break;
        }
      }
      if (commentText.isEmpty && index != -1) {
        comments.removeAt(index);
      }
      else if (commentText.isNotEmpty && index != -1) {
        comments[index].message = commentText;
      }
      else if (commentText.isNotEmpty && index == -1) {
        final lineNo = _currentCommentEditingLine;
        final context = widget.lines[lineNo].trim();
        final newComment = LineComment(
          lineNumber: lineNo,
          message: commentText,
          context: context,
          fileName: fileName,
        ).deepCopy();
        comments.add(newComment);
      }
      _commentEditor = null;
      _currentCommentEditingLine = -1;
      widget.lineCommentController?.notify();
    });
  }

  Widget buildLineNumbersMargin(BuildContext context) {
    final textStyle = createTextStyle(context).merge(TextStyle(color: Colors.black38));
    final lineHeight = LineCommentableTextPainter.calculateLineHeight(textStyle);
    final size = Size(48, lineHeight * widget.linesCount);
    final painter = LineNumbersPainter(widget.linesCount, textStyle);
    final lineNumbersView = CustomPaint(painter: painter, size: size);

    final lineNumbersBox = Container(
      child: lineNumbersView,
      constraints: BoxConstraints(
        minWidth: 50,
        maxWidth: 50,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: borderColor),
          left: BorderSide(color: borderColor),
          bottom: BorderSide(color: borderColor),
          right: BorderSide(color: borderColor, style: BorderStyle.solid),
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(10),
          bottomLeft: Radius.circular(10),
        ),
      ),
      padding: EdgeInsets.fromLTRB(8, 8, 8, 8),
    );
    return lineNumbersBox;
  }


  Widget buildTextViewer(BuildContext context) {
    final codeTextStyle = createTextStyle(context);
    final contentView = SelectableText(
      widget.text,
      style: codeTextStyle,
    );
    return contentView;
  }

  double mainContentWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    double horizontalMargins = (screenWidth - maxWidgetWidth) / 2;
    if (horizontalMargins < 0) {
      horizontalMargins = 0;
    }
    double result = screenWidth - horizontalMargins * 2 - 32;
    if (widget.withLineNumbers) {
      result -= 50;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    double contentWidth = mainContentWidth(context);

    List<Widget> rowItems = [];

    if (widget.withLineNumbers) {
      rowItems.add(buildLineNumbersMargin(context));
    }

    final contentView = buildEditorView(context);
    final contentScrollView = SingleChildScrollView(
      child: contentView,
      scrollDirection: Axis.horizontal,
    );

    final constraints = BoxConstraints(
      minWidth: contentWidth,
      maxWidth: contentWidth,
      minHeight: 50,
    );

    final contentViewBox = Container(
      child: contentScrollView,
      constraints: constraints,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(10),
          bottomRight: Radius.circular(10),
          topLeft: widget.withLineNumbers? Radius.zero : Radius.circular(10),
          bottomLeft: widget.withLineNumbers? Radius.zero : Radius.circular(10),
        ),
      ),
      padding: EdgeInsets.fromLTRB(8, 8, 8, 8),
    );

    rowItems.add(contentViewBox);

    final result = Container(
      child: Row(children: rowItems),
      margin: EdgeInsets.fromLTRB(8, 4, 8, 20),
    );

    return result;
  }
}