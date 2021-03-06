import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:protobuf/protobuf.dart';
import '../controllers/connection_controller.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'screen_base.dart';
import '../utils/csv_parser.dart';
import '../utils/utils.dart';
import '../widgets/unified_widgets.dart';



class UsersImportCSVScreen extends BaseScreen {
  UsersImportCSVScreen({required User loggedInUser}): super(loggedUser: loggedInUser);
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

  Map<String, bool> separators = {
    'Запятая': true, 'Точка с запятой': true, 'Пробел': false, 'Табуляция': true
  };

  List<String> fields = ['Фамилия', 'Имя', 'Отчество', 'Группа', 'Email'];

  Map<String, bool> options = {
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
    Container separatorsWidget = Container(
      child: createParametersBoolGroup(context, 'Разделители', separators)
    );
    Container optionsWidget = Container(
        child: createParametersBoolGroup(context, 'Опции', options)
    );
    Widget allOptions = Column(children: [SizedBox(height: 20), separatorsWidget, optionsWidget],);
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

  @override
  Widget buildCentralWidget(BuildContext context) {
    return Column(children: _buildCentralWidgetComponents(context));
  }


  final Map<int,int> _selectedColumnFields = {};
  final TextEditingController _groupForAll = TextEditingController();

  Widget _buildReviewTableComponents(BuildContext context, int columnsCount) {
    List<Widget> items = List.empty(growable: true);
    Map<int, Widget> children = {};
    children[0] = Text('[ничего]');
    for (int i=0; i<fields.length; i++) {
      children[i+1] = Text(fields[i]);
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
        child: Text('Столбец ${i+1}:')
      );
      items.add(Row(children: [
        colName, chooser, Spacer()
      ],));
    }
    if (noGroupChosen) {
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

  bool get noGroupChosen {
    bool result = true;
    for (final chosen in _selectedColumnFields.values) {
      if ((chosen - 1) == fields.indexOf('Группа')) {
        result = false;
        break;
      }
    }
    return result;
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
        child: Text('Столбец ${i+1}', textAlign: TextAlign.center),
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
        comaAsDelimiter: separators['Запятая']!,
        semicolonAsDelimiter: separators['Точка с запятой']!,
        spacesAsDelimiter: separators['Пробел']!,
        tabAsDelimiter: separators['Табуляция']!,
        escapedStrings: options['Литералы в кавычках']!,
        skipFirstRow: options['Пропустить 1 строку']!,
    );
    List<List<String>> csvTable = parser.parseTable(sourceCSV);
    setState(() {
      _csvPreview = csvTable;
      if (_csvPreview!.isNotEmpty) {
        _selectedColumnFields.clear();
        int colsCount = _csvPreview![0].length;
        for (int i=0; i<colsCount; i++) {
          _selectedColumnFields[i] = 0;
        }
      }
    });
  }

  void _createUsersFromCsvData() {
    int lastNameIndex = 1 + fields.indexOf('Фамилия');
    int firstNameIndex = 1 + fields.indexOf('Имя');
    int midNameIndex = 1 + fields.indexOf('Отчество');
    int groupNameIndex = 1 + fields.indexOf('Группа');
    int emailIndex = 1 + fields.indexOf('Email');
    int firstNameCol = -1;
    int lastNameCol = -1;
    int midNameCol = -1;
    int groupNameCol = -1;
    int emailCol = -1;
    for (MapEntry<int,int> x in _selectedColumnFields.entries) {
      if (x.value == firstNameIndex) {
        firstNameCol = x.key;
      }
      if (x.value == lastNameIndex) {
        lastNameCol = x.key;
      }
      if (x.value == midNameIndex) {
        midNameCol = x.key;
      }
      if (x.value == groupNameIndex) {
        groupNameCol = x.key;
      }
      if (x.value == emailIndex) {
        emailCol = x.key;
      }
    }
    List<User> users = [];
    for (int i=0; i<_csvPreview!.length; i++) {
      List<String> row = _csvPreview![i];
      final user = User(
        defaultRole: Role.ROLE_STUDENT,
        firstName: row[firstNameCol],
        lastName: row[lastNameCol],
        midName: midNameCol==-1? '' : row[midNameCol],
        email: emailCol==-1? '' : row[emailCol],
        groupName: groupNameCol==-1? '' : row[groupNameCol]
      ).deepCopy();
      users.add(user);
    }
    _users = users;
  }
  void _checkData() {
    int firstNameIndex = 1 + fields.indexOf('Фамилия');
    int lastNameIndex = 1 + fields.indexOf('Имя');
    bool hasFirstName = _selectedColumnFields.values.contains(firstNameIndex);
    bool hasLastname = _selectedColumnFields.values.contains(lastNameIndex);
    if (hasFirstName && hasLastname) {
      _createUsersFromCsvData();
    }
  }

  bool _submitInProgress = false;
  void _submit() {
    setState(() {
      _submitInProgress = true;
    });
    UserManagementClient service = ConnectionController.instance!.usersService;
    if (noGroupChosen && _groupForAll.text.trim().isNotEmpty) {
      final groupName = _groupForAll.text.trim();
      for (final user in _users!) {
        user.groupName = groupName;
      }
    }
    service.batchCreateStudents(UsersList(users: _users)).then((value) {
      setState(() {
        _errorMessage = null;
        _submitInProgress = false;
        Navigator.pop(context);
      });
    }).onError((error, stackTrace) {
      setState(() {
        _errorMessage = error.toString();
        _submitInProgress = false;
      });
    });
  }

  @override
  List<ScreenSubmitAction> submitActions(BuildContext context) {
    return [ScreenSubmitAction(
      title: _submitInProgress? 'Сохранение...' : 'Сохранить',
      onAction: _users==null || _submitInProgress ? null : _submit
    )];
  }




}