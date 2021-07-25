import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:yajudge_client/utils/utils.dart';

class YTextButton extends StatelessWidget {
  final String title;
  final VoidCallback? action;
  final Color? color;
  double? fontSize;
  double? padding;
  YTextButton(String title, VoidCallback? action, {this.color, this.fontSize, this.padding})
      : title = title, action = action, super();

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: action,
      child: Text(title, style: TextStyle(
          color: color,
          fontSize: fontSize
      ))
    );
  }
}

class YTextField extends StatelessWidget {
  final TextEditingController controller;
  final int? maxLines;
  final bool? showCursor;
  final bool? noBorders;

  YTextField({
    required this.controller,
    this.maxLines,
    this.showCursor,
    this.noBorders,
  }) : super();

  @override
  Widget build(BuildContext context) {
    InputDecoration? inputDecoration;
    if (noBorders!=null && noBorders!) {
      inputDecoration = null;
    } else {
      inputDecoration = InputDecoration();
    }
    return Padding(
        padding: EdgeInsets.all(8),
        child: TextField(
          expands: true,
          controller: controller,
          decoration: null,
          maxLines: maxLines,
          showCursor: showCursor,
        )
    );
  }
}

class YCheckBox extends StatelessWidget {
  final ValueChanged<bool>? action;
  final bool initialValue;

  YCheckBox(bool initialValue, ValueChanged<bool>? action)
    : this.initialValue = initialValue, this.action = action, super() ;

  @override
  Widget build(BuildContext context) {
    final ValueChanged<bool?>? action2;
    if (action != null) {
      action2 = (bool? value) {
        action!(value!);
      };
    } else {
      action2 = null;
    }
    return Checkbox(
        value: initialValue,
        onChanged: action2
    );
  }

}

class YCardLikeButton extends StatelessWidget {
  final VoidCallback? action;
  final String title;
  final Icon? leadingIcon;
  final String? subtitle;

  YCardLikeButton(this.title, this.action, {this.leadingIcon, this.subtitle}) : super();

  @override
  Widget build(BuildContext context) {
    MouseCursor cursor;
    if (action == null) {
      cursor = SystemMouseCursors.basic;
    } else {
      cursor = SystemMouseCursors.click;
    }
    List<Widget> columnItems = List.empty(growable: true);
    columnItems.add(Text(title,
      style: Theme.of(context).textTheme.headline6,
    ));
    if (subtitle != null) {
      columnItems.add(Padding(
        padding: EdgeInsets.fromLTRB(0, 8, 0, 4),
        child: Text(subtitle!,
            style: Theme.of(context).textTheme.subtitle2!.copyWith(
              color: Colors.black45
            )
        ),
      ));
    }
    List<Widget> rowItems = List.empty(growable: true);
    if (leadingIcon != null) {
      rowItems.add(
        Padding(
          child: leadingIcon!,
          padding: EdgeInsets.fromLTRB(16, 0, 0, 0),
        )
      );
    }
    rowItems.add(Expanded(
      child: Container(
        child: Column(
          children: columnItems,
          crossAxisAlignment: CrossAxisAlignment.start,
        ),
        padding: EdgeInsets.fromLTRB(20, 0, 0, 0),
      )
    ));
    Widget cardContainer = Container(
      child: Row(children: rowItems),
    );
    Color buttonColor = Theme.of(context).primaryColor;
    buttonColor = Color.alphaBlend(Color.fromARGB(230, 240, 240, 240), buttonColor);
    return ElevatedButton(
      style: ButtonStyle(
        backgroundColor: MaterialStateProperty.all(buttonColor),
        minimumSize: MaterialStateProperty.all(Size.fromHeight(80)),
      ),
      child: cardContainer,
      onPressed: action,
    );
  }
}

class AlwaysDisabledFocusNode extends FocusNode {
  @override
  bool get hasFocus => false;
}
