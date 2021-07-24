import 'package:yajudge_client/screens/screen_base.dart';
import 'package:yajudge_client/widgets/unified_widgets.dart';
import 'package:yajudge_client/wsapi/courses.dart';

import '../app.dart';
import '../wsapi/users.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class DashboardScreen extends BaseScreen {
  @override
  State<StatefulWidget> createState() => DashboardScreenState();
}


class DashboardScreenState extends BaseScreenState {

  DashboardScreenState() : super(title: 'Главная');

  User? _currentUser = AppState.instance.userProfile;
  CoursesList _coursesList = AppState.instance.coursesList;


  List<Widget> _createMyCourses() {
    if (_coursesList.courses.isEmpty) {
      return List.empty();
    }
    List<Widget> result = List.empty(growable: true);
    Text title = Text(
      'Мои курсы',
      style: Theme.of(context).textTheme.headline6,
    );
    result.add(Padding(child: title, padding: EdgeInsets.fromLTRB(0, 30, 0, 20)));
    for (CourseListEntry e in _coursesList.courses) {
      String title = e.course.name;
      String? roleTitle;
      if (e.role != UserRole_Student) {
        roleTitle = 'Вид глазами студента';
      }
      String link = '/' + e.course.urlPrefix;
      VoidCallback action = () {
        Navigator.pushNamed(context, link);
      };
      YCardLikeButton button = YCardLikeButton(title, action, subtitle: roleTitle);
      result.add(button);
    }
    return result;
  }

  List<Widget> _createAdminEntries() {
    if (!isAdministrator()) {
      return List.empty();
    }
    List<Widget> result = List.empty(growable: true);
    Text title = Text(
      'Администрирование',
      style: Theme.of(context).textTheme.headline6,
    );
    result.add(Padding(child: title, padding: EdgeInsets.fromLTRB(0, 30, 0, 20)));
    {
      String title = 'Управление пользователями';
      String subtitle = 'Добавление, удаление и сброс паролей';
      String link = '/users';
      VoidCallback action = () {
        Navigator.pushNamed(context, link);
      };
      YCardLikeButton button = YCardLikeButton(
          title, action, subtitle: subtitle);
      result.add(button);
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    AppState.instance.registerUserChangedCallback((User? user, CoursesList courseList) {
      setState((){
        _currentUser = user;
        _coursesList = courseList;
      });
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  bool isAdministrator() {
    User? user = AppState.instance.userProfile;
    if (user == null) {
      return false;
    }
    int userRole = user.defaultRole!;
    return userRole == UserRole_Administrator;
  }


  @override
  Widget buildCentralWidgetCupertino(BuildContext context) {
    List<Widget> items = List.empty(growable: true);
    items.addAll(_createMyCourses());
    items.addAll(_createAdminEntries());
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        // color: Theme.of(context).backgroundColor.withAlpha(30)
      ),
      constraints: BoxConstraints(
        minWidth: MediaQuery.of(context).size.width - 300,
        minHeight: MediaQuery.of(context).size.height - 96,
      ),
      child: Column(
        children: items,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
      ),
    );
  }

  @override
  Widget buildCentralWidgetMaterial(BuildContext context) {
    return buildCentralWidgetCupertino(context);
  }
}
