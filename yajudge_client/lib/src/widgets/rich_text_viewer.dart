import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:universal_html/html.dart' as html;
import 'package:markdown/markdown.dart' as md;
import 'package:universal_html/parsing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yajudge_common/yajudge_common.dart';

class RichTextViewer extends StatelessWidget {
  final String content;
  final String contentType;
  final TextTheme theme;
  final bool wrapInScroll;
  final FileSet? resources;
  late final html.HtmlDocument? _htmlDocument;
  late final TextSpan? _data;
  late final String? _markdownPreprocessed;
  late final Map<String,TextStyle> _tagStyles;
  late final RegExp _spaceNormalizer;

  RichTextViewer(this.content, this.contentType, {
    required this.theme,
    this.resources,
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
      _htmlDocument = parseHtmlDocument(content);
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
            text: '${last.text!} ',
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
            text = ' $text';
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

  void _processLink(String text, String? href, String title) {
    if (href != null) {
      Uri uri = Uri.parse(href);
      launchUrl(uri);
    }
  }

  Widget resourceImageBuilder(Uri uri, String? title, String? alt) {
    Uint8List bytes = Uint8List(0);
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return Image.network(uri.toString());
    }
    if (resources == null) {
      return Image.memory(bytes, width: 0, height: 0);
    }
    for (final resource in resources!.files) {
      final resourceName = resource.name;
      if (resourceName == uri.path) {
        bytes = Uint8List.fromList(resource.data);
        break;
      }
    }
    if (bytes.isNotEmpty) {
      return Image.memory(bytes);
    }
    else {
      return Image.memory(bytes, width: 0, height: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget textViewer;
    if (contentType == 'text/html') {
      RichText richText = RichText(
        textScaleFactor: 1.2,
        text: _data!,
      );
      textViewer = richText;
    } else if (contentType == 'text/markdown') {
      TextStyle mainTextStyle = theme.bodyText1!
          // .merge(GoogleFonts.ptSans())
          .merge(TextStyle(fontFamily: 'PT Sans'))
          .merge(TextStyle(letterSpacing: 1.05))
          .merge(TextStyle(height: 1.5))
      ;
      TextStyle codeTextStyle = theme.bodyText1!
          // .merge(GoogleFonts.ptMono())
          .merge(TextStyle(fontFamily: 'PT Mono'))
          .merge(TextStyle(letterSpacing: 1.1))
          .merge(TextStyle(height: 1.5))
      ;
      TextStyle h2TextStyle = theme.headline5!
          // .merge(GoogleFonts.ptSansCaption())
          .merge(TextStyle(fontFamily: 'PT Sans Caption'))
          .merge(TextStyle(color: Theme.of(context).colorScheme.primary))
          .merge(TextStyle(height: 2.5))
      ;
      TextStyle h3TextStyle = theme.headline6!
          // .merge(GoogleFonts.ptSans())
          .merge(TextStyle(fontFamily: 'PT Sans'))
          .merge(TextStyle(color: Theme.of(context).colorScheme.primary.withAlpha(200)))
          .merge(TextStyle(height: 1.8))
      ;
      MarkdownBody markdown = MarkdownBody(
        styleSheet: MarkdownStyleSheet(
          textScaleFactor: 1.15,
          p: mainTextStyle,
          pPadding: EdgeInsets.fromLTRB(0, 0, 0, 8),
          codeblockDecoration: BoxDecoration(
            color: Color.fromARGB(255, 245, 245, 245),
            borderRadius: BorderRadius.circular(4),
          ),
          code: codeTextStyle,
          blockquote: codeTextStyle,
          h2: h2TextStyle,
          h3: h3TextStyle,
        ),
        selectable: false,
        data: _markdownPreprocessed!,
        imageBuilder: resourceImageBuilder,
        extensionSet: md.ExtensionSet(
          md.ExtensionSet.gitHubFlavored.blockSyntaxes,
          [md.EmojiSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
        ),
        onTapLink: _processLink,
      );
      textViewer = markdown;
    } else {
      textViewer = Text(
        'Content type $contentType is not supported',
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
    bool headingFound = false;
    String result = '';
    for (String line in lines) {
      if (line.trim().startsWith('#') && !line.trim().startsWith('##') && !headingFound) {
        // skip heading
        headingFound = true;
      } else {
        result += '$line\n';
      }
    }
    return result;
  }

}