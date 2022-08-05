import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../controllers/connection_controller.dart';
import 'screen_base.dart';
import 'package:yajudge_common/yajudge_common.dart';

class UsersScreen extends BaseScreen {
  UsersScreen({required User user}): super(loggedUser: user);

  @override
  State<StatefulWidget> createState() => UsersScreenState() ;
}

class UsersScreenState extends BaseScreenState {
  UsersFilter? _filter;
  List<User>? _usersToShow;
  List<bool>? _usersSelected;
  String? _loadError;
  final RegExp _rxNumbers = RegExp(r'\d+');
  late TextEditingController _searchField;

  static final Map<Role, String> roleNames = {
    Role.ROLE_ANY: '[ любая роль ]',
    Role.ROLE_ADMINISTRATOR: 'Администратор',
    Role.ROLE_LECTURER: 'Лектор',
    Role.ROLE_TEACHER: 'Семинарист',
    Role.ROLE_TEACHER_ASSISTANT: 'Учебный ассистент',
    Role.ROLE_STUDENT: 'Студент',
  };
  static final Map<String, Role> namedRoles =
      roleNames.map((key, value) => MapEntry(value, key));
  final String searchPlaceholderText = 'Имя или группа';

  UsersScreenState() : super(title: 'Управление пользователями') ;

  void setUsersFilter(UsersFilter? filter) {
    if (filter == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _filter = null;
        _usersToShow = null;
        _usersSelected = null;
        _loadError = null;
      });
      return;
    }
    UserManagementClient service = ConnectionController.instance!.usersService;
    service.getUsers(filter).then((UsersList usersList) {
      if (!mounted) {
        return;
      }
      setState(() {
        _usersToShow = List.from(usersList.users);
        _usersSelected = List.filled(_usersToShow!.length, false);
        _filter = filter;
        _loadError = null;
      });
    }).onError((error, stackTrace) {
      if (!mounted) {
        return;
      }
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
    setUsersFilter(UsersFilter(partialStringMatch: true));
    _searchField = TextEditingController();
  }

  void processSearch(String? search) {
    UsersFilter filter = UsersFilter(partialStringMatch: true)..role = Role.ROLE_ANY..user = User();
    search ??= _searchField.text;
    if (_rxNumbers.hasMatch(search)) {
      filter.user.groupName = search.trim();
    } else {
      List<String> nameParts = search.trim().split(' ');
      if (nameParts[0] == '-' || nameParts[0] == '*' || nameParts[0] == '?') {
        filter.user.lastName = '';
      } else {
        filter.user.lastName = nameParts[0];
      }
      if (nameParts.length > 1) {
        filter.user.firstName = nameParts[1];
      }
      if (nameParts.length > 2) {
        filter.user.midName = nameParts[2];
      }
    }
    setUsersFilter(filter);
  }



  Widget _createSearchBoxWidget(BuildContext context) {
    final searchWidgets = <Widget>[
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

  static String getUserFullName(User user) {
    String result = '${user.lastName} ${user.firstName}';
    if (user.midName.isNotEmpty) {
      result += ' ${user.midName}';
    }
    return result;
  }

  Widget _buildUsersTable(BuildContext context) {
    List<TableRow> items = List.empty(growable: true);
    if (_usersToShow != null) {
      for (int i=0; i<_usersToShow!.length; i++) {
        Widget entryCheckBox = Checkbox(
            value: _usersSelected![i],
            onChanged: (bool? val) => setState(() => _usersSelected![i] = val!)
        );
        User user = _usersToShow![i];
        String groupText = user.groupName.isNotEmpty ? user.groupName : '---';
        TableRow item = TableRow(
          children: [
            TableCell(child: entryCheckBox),
            TableCell(child: Text(user.id.toString())),
            TableCell(child: MouseRegion(
              child: GestureDetector(
                child: Text(getUserFullName(user)),
                onTap: () => _navigateToUser(user.id.toInt()),
              ),
              cursor: SystemMouseCursors.click,
            )),
            TableCell(child: Text(groupText)),
            TableCell(child: Text(roleNames[user.defaultRole]!)),
          ]
        );
        items.add(item);
      }
    }
    if (_loadError != null) {
      return Text(_loadError!, style: TextStyle(color: Theme.of(context).errorColor));
    }
    if (_usersToShow != null && _usersToShow!.isEmpty) {
      return Text('Ничего не найдено');
    }
    BorderSide borderSide = BorderSide(
      color: Theme.of(context).colorScheme.secondary.withAlpha(50)
    );
    if (_usersToShow != null) {
      Widget selectAllCheckbox = Checkbox(
          value: _usersSelected!.any((element) => element),
          onChanged: (bool? val) => setState((){
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
        0: FixedColumnWidth(50),
        1: FixedColumnWidth(40),
        2: FlexColumnWidth(),
        3: FixedColumnWidth(80),
        4: FixedColumnWidth(150),
      },
      children: items,
    );
  }

  @override
  Widget buildCentralWidget(BuildContext context) {
    Widget searchBox = _createSearchBoxWidget(context);
    Widget usersTable = _buildUsersTable(context);
    return Column(children: [ searchBox, usersTable ]);
  }

  void _deleteSelectedItems() {
    UserManagementClient service = ConnectionController.instance!.usersService;
    UsersList toDelete = UsersList();
    assert (_usersToShow != null && _usersSelected != null);
    assert (_usersToShow!.length == _usersSelected!.length);
    for (int i=0; i<_usersToShow!.length; i++) {
      if (_usersSelected![i]) {
        toDelete.users.add(_usersToShow![i]);
      }
    }
    service.batchDeleteUsers(toDelete)
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


  Widget _buildConfirmDeleteDialog() {
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
    Navigator.pushNamed(context, '/users/$userId').then((_) => _reloadCurrentFilter());
  }

  void _navigateToImportFromCSV() {
    Navigator.pushNamed(context, '/users/import_csv').then((_) => _reloadCurrentFilter());
  }

  @override
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

  @override
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
