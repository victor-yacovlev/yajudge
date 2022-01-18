import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../client_app.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'screen_base.dart';
import '../utils/csv_parser.dart';
import '../utils/utils.dart';
import '../widgets/unified_widgets.dart';



class UsersImportCSVScreen extends BaseScreen {
  @override
  State<StatefulWidget> createState() => UsersImportCSVScreenState();
}

class UsersImportCSVScreenState extends BaseScreenState {

  String? _errorMessage;
  List<User>? _users;
  List<List<String>>? _csvPreview;
  late TextEditingController _sourceTextController;

  UsersImportCSVScreenState() : super(title: 'Импорт CSV') ;

  @override
  void initState() {
    super.initState();
    _sourceTextController = TextEditingController();
  }

  void _loadContentFromFile(Uint8List content) {
    String text = utf8.decode(content);
    setState(() {
      _errorMessage = null;
      _sourceTextController.text = text;
    });
  }

  void _pickFileToImport() {
    PlatformsUtils utils = PlatformsUtils.getInstance();
    utils.pickLocalFileOpen(['.csv', '.txt']).then((LocalFile? localFile) {
      if (localFile==null) {
        debugPrintSynchronously('Open dialog canceled');
        return;
      }

      localFile.readContents().then(_loadContentFromFile).onError((error, stackTrace) {
        setState(() {
          _errorMessage = error.toString();
        });
      });

    }).onError((error, stackTrace) {
      setState(() {
        _errorMessage = error.toString();
      });
    });

  }

  Widget _createSourceItems(BuildContext context) {
    Widget importFromFileButton = YTextButton('Загрузить из файла...', _pickFileToImport);
    Widget label = Text('Исходные данные');
    Widget sourceEdit = YTextField(
      controller: _sourceTextController,
      maxLines: null,
      noBorders: true,
      showCursor: true,
    );
    Widget sourceEditView = SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: sourceEdit,
    );
    Widget firstRow = Row(
      children: [label, Spacer(), importFromFileButton],
    );
    return Column(
      children: [
        firstRow,
        Container(
          decoration: BoxDecoration(
            border: Border.fromBorderSide(BorderSide(
              color: Theme.of(context).primaryColor
            )),
          ),
          constraints: BoxConstraints(maxHeight: 300, minHeight: 250),
          child: MouseRegion(
            cursor: SystemMouseCursors.text,
            child: sourceEditView,
          )
        )
      ],
    );
  }

  Map<String, bool> Delimeters = {
    'Запятая': true, 'Точка с запятой': true, 'Пробел': false, 'Табуляция': true
  };

  List<String> Fields = ['Фамилия', 'Имя', 'Отчество', 'Группа', 'Email'];

  Map<String, bool> Options = {
    'Пропустить 1 строку': true, 'Литералы в кавычках': false,
  };

  Widget createParametersBoolGroup(
      BuildContext context, String title,
      Map<String, bool> paramsStorage)
  {
    List<Widget> items = List.empty(growable: true);
    items.add(Text(title));
    for (String key in paramsStorage.keys) {
      items.add(Row(
        children: [
          YCheckBox(
            paramsStorage[key]!,
            (v) => setState(() { paramsStorage[key] = v; })
          ),
          Expanded(child: Text(key)),
        ],
      ));
    }
    return Column(children: items,);
  }

  Widget _createParametersCheck(BuildContext context) {
    Container delimetersWidget = Container(
      child: createParametersBoolGroup(context, 'Разделители', Delimeters)
    );
    Container optionsWidget = Container(
        child: createParametersBoolGroup(context, 'Опции', Options)
    );
    Widget allOptions = Column(children: [SizedBox(height: 20), delimetersWidget, optionsWidget],);
    return Container(
      child: SingleChildScrollView(
        child: allOptions,
        scrollDirection: Axis.vertical,
      ),
      constraints: BoxConstraints(maxHeight: 550),
    );
  }

  List<Widget> _buildCentralWidgetComponents(BuildContext context) {
    Widget sourceWidgets = Row(
      children: [
        Expanded(
          child: _createSourceItems(context),
        ),
        SizedBox(width: 20,),
        Container(
          constraints: BoxConstraints(maxWidth: 250),
          child: _createParametersCheck(context),
        ),
      ]
    );
    Text statusText;
    if (_errorMessage != null) {
      statusText = Text(_errorMessage!, style: TextStyle(color: Theme.of(context).errorColor));
    } else if (_csvPreview == null) {
      statusText = Text('Нажмите кнопку "Импортировать" и проверьте результат');
    } else {
      statusText = Text('Предварительный просмотр:');
    }
    YTextButton parseButton = YTextButton('Импортировать', _doParsing);
    Widget actionsRow = Row(
      children: [
        Expanded(child: statusText),
        Container(
          child: parseButton,
          constraints: BoxConstraints(maxWidth: 200),
        )
      ],
    );
    List<Widget> components = [sourceWidgets, actionsRow];
    Table? result = _buildPreviewTableContents(context);
    if (result != null) {
      components.add(result);
      components.add(SizedBox(height: 10));
      int colsCount = _csvPreview![0].length;
      components.add(_buildReviewTableComponents(context, colsCount));
    }
    // components.add(SizedBox(height: 100));
    return components;
  }

  Widget buildCentralWidgetCupertino(BuildContext context) {
    return Column(children: _buildCentralWidgetComponents(context));
  }

  Widget buildCentralWidget(BuildContext context) {
    return Column(children: _buildCentralWidgetComponents(context));
  }


  Map<int,int> _selectedColumnFields = Map();
  TextEditingController _groupForAll = TextEditingController();

  Widget _buildReviewTableComponents(BuildContext context, int columnsCount) {
    List<Widget> items = List.empty(growable: true);
    Map<int, Widget> children = Map();
    children[0] = Text('[ничего]');
    for (int i=0; i<Fields.length; i++) {
      children[i+1] = Text(Fields[i]);
    }
    for (int i=0; i<columnsCount; i++) {
      Widget chooser = Container(
        width: 600,
        margin: EdgeInsets.all(4),
        child: CupertinoSlidingSegmentedControl(
          groupValue: _selectedColumnFields[i],
          // backgroundColor: Colors.blue.shade100,
          children: children,
          onValueChanged: (int? value) {
            if (value != null) {
              setState(() {
                for (int j in _selectedColumnFields.keys) {
                  if (_selectedColumnFields[j] == value) {
                    _selectedColumnFields[j] = 0;
                  }
                }
                _selectedColumnFields[i] = value;
                _checkData();
              });
            }
          },
        )
      );
      Widget colName = Container(
        width: 100,
        child: Text('Столбец '+(i+1).toString()+':')
      );
      items.add(Row(children: [
        colName, chooser, Spacer()
      ],));
    }
    bool noGroupChoosen = true;
    for (int choosen in _selectedColumnFields.values) {
      if ((choosen - 1) == Fields.indexOf('Группа')) {
        noGroupChoosen = false;
        break;
      }
    }
    if (noGroupChoosen) {
      items.add(TextField(
        controller: _groupForAll,
        decoration: InputDecoration(
          labelText: 'Назначить всем группу',
        ),
        showCursor: true,
      ));
    }
    return Container(child: Column(children: items));
  }

  Table? _buildPreviewTableContents(BuildContext context) {
    if (_csvPreview == null || _csvPreview!.isEmpty) {
      return null;
    }
    List<TableRow> rows = List.empty(growable: true);
    int columnsCount = _csvPreview![0].length;
    List<TableCell> headerCells = List.empty(growable: true);
    for (int i=0; i<columnsCount; i++) {
      headerCells.add(TableCell(
        child: Text('Столбец '+(i+1).toString(), textAlign: TextAlign.center),
      ));
    }
    TableRow headerRow = TableRow(
      decoration: BoxDecoration(
        color: Theme.of(context).secondaryHeaderColor,
      ),
      children: headerCells
    );
    rows.add(headerRow);
    for (int i=0; i<_csvPreview!.length; i++) {
      List<TableCell> cells = List.empty(growable: true);
      for (int j=0; j<_csvPreview![i].length; j++) {
        String data = _csvPreview![i][j];
        cells.add(TableCell(child: Text(data, textAlign: TextAlign.center,)));
      }
      rows.add(TableRow(children: cells));
    }
    return Table(
      border: TableBorder.all(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: rows,
    );
  }

  void _doParsing() {
    String sourceCSV = _sourceTextController.text.trim();
    if (sourceCSV.isEmpty) {
      setState(() {
        _errorMessage = 'Ошибка импорта: пустой текст';
      });
      return;
    }
    CsvParser parser = CsvParser(
        comaAsDelimiter: Delimeters['Запятая']!,
        semicolonAsDelimiter: Delimeters['Точка с запятой']!,
        spacesAsDelimiter: Delimeters['Пробел']!,
        tabAsDelimiter: Delimeters['Табуляция']!,
        escapedStrings: Options['Литералы в кавычках']!,
        skipFirstRow: Options['Пропустить 1 строку']!,
    );
    List<List<String>> csvTable = parser.parseTable(sourceCSV);
    setState(() {
      _csvPreview = csvTable;
      if (_csvPreview!.length > 0) {
        _selectedColumnFields.clear();
        int colsCount = _csvPreview![0].length;
        for (int i=0; i<colsCount; i++) {
          _selectedColumnFields[i] = 0;
        }
      }
    });
  }

  void _createUsersFromCsvData() {
    int lastNameIndex = 1 + Fields.indexOf('Фамилия');
    int firstNameIndex = 1 + Fields.indexOf('Имя');
    int midNameIndex = 1 + Fields.indexOf('Отчество');
    int groupNameIndex = 1 + Fields.indexOf('Группа');
    int emailIndex = 1 + Fields.indexOf('Email');
    int firstNameCol = -1;
    int lastNameCol = -1;
    int midNameCol = -1;
    int groupNameCol = -1;
    int emailCol = -1;
    for (MapEntry<int,int> x in _selectedColumnFields.entries) {
      if (x.value == firstNameIndex)
        firstNameCol = x.key;
      if (x.value == lastNameIndex)
        lastNameCol = x.key;
      if (x.value == midNameIndex)
        midNameCol = x.key;
      if (x.value == groupNameIndex)
        groupNameCol = x.key;
      if (x.value == emailIndex)
        emailCol = x.key;
    }
    List<User> users = List.empty(growable: true);
    for (int i=0; i<_csvPreview!.length; i++) {
      List<String> row = _csvPreview![i];
      final user = User(
        defaultRole: Role.ROLE_STUDENT,
        firstName: row[firstNameCol],
        lastName: row[lastNameCol],
        midName: midNameCol==-1? '' : row[midNameCol],
        email: emailCol==-1? '' : row[emailCol],
        groupName: groupNameCol==-1? '' : row[groupNameCol]
      );
      users.add(user);
    }
    _users = users;
  }
  void _checkData() {
    int firstNameIndex = 1 + Fields.indexOf('Фамилия');
    int lastNameIndex = 1 + Fields.indexOf('Имя');
    bool hasFirstName = _selectedColumnFields.values.contains(firstNameIndex);
    bool hasLastname = _selectedColumnFields.values.contains(lastNameIndex);
    if (hasFirstName && hasLastname) {
      _createUsersFromCsvData();
    }
  }

  bool _sumbitInProgress = false;
  void _submit() {
    setState(() {
      _sumbitInProgress = true;
    });
    UserManagementClient service = AppState.instance.usersService;
    service.batchCreateStudents(UsersList(users: _users)).then((value) {
      setState(() {
        _errorMessage = null;
        _sumbitInProgress = false;
        Navigator.pop(context);
      });
    }).onError((error, stackTrace) {
      setState(() {
        _errorMessage = error.toString();
        _sumbitInProgress = false;
      });
    });
  }

  ScreenSubmitAction? submitAction(BuildContext context) {
    return ScreenSubmitAction(
      title: _sumbitInProgress? 'Сохранение...' : 'Сохранить',
      onAction: _users==null || _sumbitInProgress ? null : _submit
    );
  }




}