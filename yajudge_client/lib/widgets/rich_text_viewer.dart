import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:universal_html/html.dart' as html;
import 'package:markdown/markdown.dart' as md;
import 'package:universal_html/parsing.dart';

class RichTextViewer extends StatelessWidget {
  final String content;
  final String contentType;
  final TextTheme theme;
  final bool wrapInScroll;
  html.HtmlDocument? _htmlDocument;
  TextSpan? _data;
  String? _markdownPreprocessed;
  late Map<String,TextStyle> _tagStyles;
  late RegExp _spaceNormalizer;

  RichTextViewer(this.content, this.contentType, {
    required this.theme,
    this.wrapInScroll = false
  }) : super() {
    _tagStyles = {
      'p': theme.bodyText1!.merge(TextStyle(fontWeight: FontWeight.normal)),
      'li': theme.bodyText1!.merge(TextStyle(fontWeight: FontWeight.normal)),
      'tt': theme.bodyText1!.merge(TextStyle(fontFamily: 'Courier')),
      'pre': theme.bodyText1!.merge(TextStyle(fontFamily: 'Courier')),
    };
    _spaceNormalizer = RegExp(r'\s+');
    if (contentType == 'text/html') {
      _htmlDocument = parseHtmlDocument(this.content);
      _data = _fromHtml(_htmlDocument!);
    } else if (contentType == 'text/markdown') {
      _markdownPreprocessed = removeMarkdownHeading(content);
    }
  }

  TextSpan _fromHtml(html.HtmlDocument doc) {
    html.Node body = doc.body!;
    return _fromHtmlElement(body);
  }

  TextSpan _fromHtmlElement(html.Node root) {
    List<html.Node> childNodes = root.childNodes;
    List<TextSpan> spans = List.empty(growable: true);
    assert (root.nodeType == html.Node.ELEMENT_NODE);
    String tag = root.nodeName!.toLowerCase();
    TextStyle style = tagStyle(tag);
    for (html.Node n in childNodes) {
      int nodeType = n.nodeType;
      if (nodeType == html.Node.ELEMENT_NODE) {
        TextSpan childSpan = _fromHtmlElement(n);
        if (spans.isNotEmpty && spans.last.text!=null && spans.last.text!.isNotEmpty) {
          TextSpan last = spans.removeLast();
          spans.add(TextSpan(
            text: last.text! + ' ',
            style: last.style,
            children: last.children,
          ));
        }
        spans.add(childSpan);
      } else if (nodeType == html.Node.TEXT_NODE) {
        String nodeValue = n.nodeValue!;
        String text;
        if (tag != 'pre') {
          text = nodeValue.replaceAll(_spaceNormalizer, ' ').trim();
          if (nodeValue.startsWith(' ') && spans.isNotEmpty) {
            text = ' ' + text;
          }
        } else {
          text = nodeValue;
        }
        if (text.isNotEmpty) {
          TextSpan textSpan = TextSpan(text: text);
          spans.add(textSpan);
        }
      }
    }
    if (tag == 'p' || tag == 'pre' || tag == 'li') {
      spans.add(TextSpan(text: '\n'));
    }
    return TextSpan(
      style: style,
      children: spans
    );
  }

  TextStyle tagStyle(String tag) {
    if (_tagStyles.containsKey(tag)) {
      return _tagStyles[tag]!;
    } else {
      return TextStyle();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget textViewer;
    if (contentType == 'text/html') {
      RichText richText = RichText(
        textScaleFactor: 1.3,
        text: _data!,
      );
      textViewer = richText;
    } else if (contentType == 'text/markdown') {
      MarkdownBody markdown = MarkdownBody(
        styleSheet: MarkdownStyleSheet(
          textScaleFactor: 1.3,
          code: theme.bodyText1!.merge(TextStyle(fontFamily: 'Courier')),
        ),
        selectable: false,
        data: _markdownPreprocessed!,
        extensionSet: md.ExtensionSet(
          md.ExtensionSet.gitHubFlavored.blockSyntaxes,
          [md.EmojiSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
        ),
      );
      textViewer = markdown;
    } else {
      textViewer = Text(
        'Content type '+contentType+' is not supported',
        style: TextStyle(color: Theme.of(context).errorColor),
      );
    }
    Widget component = Container(
      child: textViewer,
      width: MediaQuery.of(context).size.width,
    );
    if (wrapInScroll) {
      return SingleChildScrollView(child: component);
    } else {
      return component;
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

}