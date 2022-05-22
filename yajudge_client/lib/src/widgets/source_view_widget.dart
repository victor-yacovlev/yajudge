import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SourceViewWidget extends StatefulWidget {
  final String text;
  final bool withLineNumbers;
  SourceViewWidget({
    required this.text,
    this.withLineNumbers = false,
    Key? key
  }): super(key: key);

  @override
  State<StatefulWidget> createState() => SourceViewWidgetState();

  int get linesCount {
    int lines = text.split('\n').length;
    if (text.endsWith('\n')) {
      lines -= 1;
    }
    return lines;
  }
}

class SourceViewWidgetState extends State<SourceViewWidget> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final codeTextStyle = theme.textTheme.bodyText1!
        // .merge(GoogleFonts.ptMono())
        .merge(TextStyle(fontFamily: 'PT Mono'))
        .merge(TextStyle(letterSpacing: 1.1));

    final borderColor = Colors.black12;

    const maxWidgetWidth = 950;

    final screenWidth = MediaQuery.of(context).size.width;
    double horizontalMargins = (screenWidth - maxWidgetWidth) / 2;
    if (horizontalMargins < 0) {
      horizontalMargins = 0;
    }
    double contentWidth = screenWidth - horizontalMargins * 2 - 32;

    List<Widget> rowItems = [];

    if (widget.withLineNumbers) {
      contentWidth -= 50;
      String lineNumbers = '';
      final linesCount = widget.linesCount;
      for (int i = 0; i < linesCount; ++i) {
        if (lineNumbers.isNotEmpty) {
          lineNumbers += '\n';
        }
        lineNumbers += '${i+1}';
      }
      final lineNumbersView = Text(lineNumbers,
          textAlign: TextAlign.right,
          style: codeTextStyle.merge(TextStyle(
            color: theme.textTheme.bodyText1!.color!.withAlpha(127),
          ))
      );

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

      rowItems.add(lineNumbersBox);
    }

    final contentView = SelectableText(widget.text, style: codeTextStyle);
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