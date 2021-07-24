import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:yajudge_client/screens/screen_base.dart';
import '../wsapi/users.dart';

class UsersScreen extends BaseScreen {
  @override
  State<StatefulWidget> createState() => UsersScreenState() ;
}

class UsersScreenState extends BaseScreenState {
  UsersFilter? _filter;
  List<User>? _usersToShow;
  List<bool>? _usersSelected;
  String? _loadError;
  RegExp _rxNumbers = RegExp(r'[0..9]+');
  late TextEditingController _searchField;

  static final Map<int, String> RoleNames = {
    UserRole_Any: '[ любая роль ]',
    UserRole_Administrator: 'Администратор',
    UserRole_Lecturer: 'Лектор',
    UserRole_Teacher: 'Семинарист',
    UserRole_TeacherAssistant: 'Учебный ассистент',
    UserRole_Student: 'Студент',
  };
  static final Map<String, int> NamedRoles =
      RoleNames.map((key, value) => MapEntry(value, key));
  final String searchPlaceholderText = 'Имя или группа';

  UsersScreenState() : super(title: 'Управление пользователями') ;

  void setUsersFilter(UsersFilter? filter) {
    if (filter == null) {
      setState(() {
        _filter = null;
        _usersToShow = null;
        _usersSelected = null;
        _loadError = null;
      });
      return;
    }
    UsersService service = UsersService.instance;
    service.getUsers(filter).then((UsersList usersList) {
      setState(() {
        _usersToShow = List.from(usersList.users);
        _usersSelected = List.filled(_usersToShow!.length, false);
        _filter = filter;
        _loadError = null;
      });
    }).onError((error, stackTrace) {
      setState(() {
        _usersToShow = null;
        _usersSelected = null;
        _loadError = error.toString();
      });
    });
  }


  void _reloadCurrentFilter() {
    if (_filter == null) {
      setUsersFilter(UsersFilter());
    } else {
      setUsersFilter(_filter);
    }
  }

  @override
  void initState() {
    super.initState();
    setUsersFilter(UsersFilter());
    _searchField = TextEditingController();
  }

  @override
  void dispose() {
    super.dispose();
  }




  void processSearch(String? search) {
    var filter = UsersFilter()..role = UserRole_Any..user = User();
    if (search == null) {
      search = _searchField.text;
    }
    if (_rxNumbers.hasMatch(search)) {
      filter.user!.groupName = search.trim();
    } else {
      List<String> nameParts = search.trim().split(' ');
      if (nameParts[0] == '-' || nameParts[0] == '*' || nameParts[0] == '?') {
        filter.user!.lastName = '';
      } else {
        filter.user!.lastName = nameParts[0];
      }
      if (nameParts.length > 1) {
        filter.user!.firstName = nameParts[1];
      }
      if (nameParts.length > 2) {
        filter.user!.midName = nameParts[2];
      }
    }
    setUsersFilter(filter);
  }

  Widget _createSearchBoxWidgetCupertino(BuildContext context) {
    final List<Widget> searchWidgets = [
      Expanded(
        child: CupertinoTextField(
          controller: _searchField,
          placeholder: searchPlaceholderText,
          onSubmitted: (name) => processSearch(name),
        )
      ),
      Container(
        child: CupertinoButton(
          child: Icon(Icons.search),
          onPressed: () => processSearch(null),
        ),
      ),
    ];
    return Container(
      padding: EdgeInsets.fromLTRB(0, 0, 0, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: searchWidgets,
      ),
    );
  }

  Widget _createSearchBoxWidgetMaterial(BuildContext context) {
    final List<Widget> searchWidgets = [
      Expanded(
        child: TextField(
          controller: _searchField,
          decoration: InputDecoration(labelText: searchPlaceholderText),
          onSubmitted: (name) => processSearch(name),
        )
      ),
      Container(
        child: ElevatedButton(
          child: Icon(Icons.search),
          onPressed: () => processSearch(null),
        ),
        margin: EdgeInsets.fromLTRB(10, 0, 0, 0),
      ),
    ];
    return Container(
      padding: EdgeInsets.fromLTRB(0, 0, 0, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: searchWidgets,
      ),
    );
  }

  Widget _createCheckbox(bool isCupertino, bool value, Function(bool?) onChanged) {
    if (isCupertino) {
      return CupertinoSwitch(value: value, onChanged: onChanged);
    } else {
      return Checkbox(value: value, onChanged: onChanged);
    }
  }
  
  Widget _buildUsersTable(BuildContext context, bool isCupertino) {
    List<TableRow> items = List.empty(growable: true);
    double minCheckboxWidth = isCupertino ? 80 : 50;
    if (_usersToShow != null) {
      for (int i=0; i<_usersToShow!.length; i++) {
        Widget entryCheckBox = _createCheckbox(
            isCupertino,
            _usersSelected![i],
            (bool? val) => setState(() => _usersSelected![i] = val!)
        );
        User user = _usersToShow![i];
        String groupText = user.groupName!=null && user.groupName!.isNotEmpty
            ? user.groupName!
            : '---';
        TableRow item = TableRow(
          children: [
            TableCell(child: entryCheckBox),
            TableCell(child: Text(user.id.toString())),
            TableCell(child: MouseRegion(
              child: GestureDetector(
                child: Text(user.fullName()),
                onTap: () => _navigateToUser(user.id),
              ),
              cursor: SystemMouseCursors.click,
            )),
            TableCell(child: Text(groupText)),
            TableCell(child: Text(RoleNames[user.defaultRole]!)),
          ]
        );
        items.add(item);
      }
    }
    if (_loadError != null) {
      return Text(_loadError!, style: TextStyle(color: Theme.of(context).errorColor));
    }
    if (_usersToShow != null && _usersToShow!.length ==0) {
      return Text('Ничего не найдено');
    }
    BorderSide borderSide = BorderSide(
      color: Theme.of(context).accentColor.withAlpha(50)
    );
    if (_usersToShow != null) {
      Widget selectAllCheckbox = _createCheckbox(
          isCupertino,
          _usersSelected!.any((element) => element),
          (bool? val) => setState((){
            for (int i=0; i<_usersSelected!.length; i++) {
              _usersSelected![i] = val!;
            }
          })
      );
      TableRow headerRow = TableRow(
        decoration: BoxDecoration(
          color: Theme.of(context).secondaryHeaderColor,
        ),
        children: [
          TableCell(child: selectAllCheckbox),
          TableCell(child: Text('ID')),
          TableCell(child: Text('Фамилия Имя Отчество')),
          TableCell(child: Text('Группа')),
          TableCell(child: Text('Роль')),
        ]
      );
      items.insert(0, headerRow);
    }
    return Table(
      border: TableBorder(
        horizontalInside: borderSide,
        top: borderSide,
        bottom: borderSide,
      ),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {
        0: FixedColumnWidth(minCheckboxWidth),
        1: FixedColumnWidth(40),
        2: FlexColumnWidth(),
        3: FixedColumnWidth(80),
        4: FixedColumnWidth(150),
      },
      children: items,
    );
  }

  @override
  Widget buildCentralWidgetCupertino(BuildContext context) {
    Widget searchBox = _createSearchBoxWidgetCupertino(context);
    Widget usersTable = _buildUsersTable(context, true);
    return Column(children: [ searchBox, usersTable ]);
  }

  @override
  Widget buildCentralWidgetMaterial(BuildContext context) {
    Widget searchBox = _createSearchBoxWidgetMaterial(context);
    Widget usersTable = _buildUsersTable(context, false);
    return Column(children: [ searchBox, usersTable ]);
  }

  void _deleteSelectedItems() {
    UsersService service = UsersService.instance;
    List<User> toDelete = List.empty(growable: true);
    assert (_usersToShow != null && _usersSelected != null);
    assert (_usersToShow!.length == _usersSelected!.length);
    for (int i=0; i<_usersToShow!.length; i++) {
      if (_usersSelected![i]) {
        toDelete.add(_usersToShow![i]);
      }
    }
    service.batchDeleteUsers(UsersList()..users=toDelete)
    .then((value) {
      setState(() {
        setUsersFilter(_filter);
      });
    })
    .onError((error, stackTrace) {
      setState(() {
        _loadError = error.toString();
        setUsersFilter(_filter);
      });
    });
  }

  Widget _buildConfirmDeleteDialogCupertino() {
    return CupertinoAlertDialog(
      title: const Text('Удалить пользователей'),
      content: SingleChildScrollView(
        child: Text('Действительно удалить? Эта операция не обратима!'),
      ),
      actions: [
        CupertinoButton(
          child: Text('Удалить',
              style: TextStyle(color: Colors.red)
          ),
          onPressed: () { _deleteSelectedItems(); Navigator.of(context).pop(); },
        ),
        CupertinoButton(
          child: Text('Отмена'),
          onPressed: () => Navigator.of(context).pop(),
        )
      ],
    );
  }

  Widget _buildConfirmDeleteDialogMaterial() {
    return AlertDialog(
      title: const Text('Удалить пользователей'),
      content: SingleChildScrollView(
        child: Text('Действительно удалить? Эта операция не обратима!'),
      ),
      actions: [
        TextButton(
          child: Text('Удалить',
            style: TextStyle(color: Colors.red)
          ),
          onPressed: () { _deleteSelectedItems(); Navigator.of(context).pop(); },
        ),
        TextButton(
          child: Text('Отмена'),
          onPressed: () => Navigator.of(context).pop(),
        )
      ],
    );
  }

  Widget _buildConfirmDeleteDialog() {
    if (isCupertino) {
      return _buildConfirmDeleteDialogCupertino();
    } else {
      return _buildConfirmDeleteDialogMaterial();
    }
  }

  void _deleteSelectedItemsButtonPressed() {
    showCupertinoDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return _buildConfirmDeleteDialog();
        }
    );
  }

  void _navigateToCreateNewUser() {
    Navigator.pushNamed(context, '/users/new').then((_) => _reloadCurrentFilter());
  }

  void _navigateToUser(int userId) {
    Navigator.pushNamed(context, '/users/' + userId.toString()).then((_) => _reloadCurrentFilter());
  }

  void _navigateToImportFromCSV() {
    Navigator.pushNamed(context, '/users/import_csv').then((_) => _reloadCurrentFilter());
  }

  ScreenActions? buildPrimaryScreenActions(BuildContext context) {
    return ScreenActions(
        rootIcon: const Icon(Icons.add),
        rootTitle: 'Добавить',
        isPrimary: true,
        actions: [
          ScreenAction(
            icon: const Icon(Icons.person),
            title: '+1 пользователь',
            onAction: _navigateToCreateNewUser,
          ),
          ScreenAction(
            icon: const Icon(Icons.table_chart_sharp),
            title: 'Импорт CSV',
            onAction: _navigateToImportFromCSV,
          )
        ]
    );
  }

  ScreenActions? buildSecondaryScreenActions(BuildContext context) {
    if (_usersSelected!=null && _usersSelected!.any((element) => element)) {
      return ScreenActions(
        rootIcon: const Icon(Icons.delete_forever),
        rootTitle: 'Удалить',
        isPrimary: false,
        onRoot: _deleteSelectedItemsButtonPressed,
      );
    }
    else {
      return null;
    }
  }

}
