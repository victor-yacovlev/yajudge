import 'screen_base.dart';
import '../utils/utils.dart';
import '../widgets/unified_widgets.dart';
import 'package:yajudge_common/yajudge_common.dart';

import '../client_app.dart';
import 'package:flutter/material.dart';

class DashboardScreen extends BaseScreen {
  @override
  State<StatefulWidget> createState() => DashboardScreenState();
}


class DashboardScreenState extends BaseScreenState {

  DashboardScreenState() : super(title: 'Главная');

  List<Widget> _createMyCourses() {
    if (AppState.instance.coursesList.courses.isEmpty) {
      return List.empty();
    }
    List<Widget> result = List.empty(growable: true);
    Text title = Text(
      'Мои курсы',
      style: Theme.of(context).textTheme.headline6,
    );
    result.add(Padding(child: title, padding: EdgeInsets.fromLTRB(0, 30, 0, 20)));
    for (CoursesList_CourseListEntry e in AppState.instance.coursesList.courses) {
      String title = e.course.name;
      String? roleTitle;
      if (e.role != Role.ROLE_STUDENT) {
        roleTitle = 'Вид глазами студента';
      }
      String link = '/' + e.course.urlPrefix + '/';
      String? subroute = PlatformsUtils.getInstance()
        .loadSettingsValue('Subroute/' + e.course.urlPrefix);
      if (subroute != null) {
        link += subroute;
      }
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

  bool isAdministrator() {
    User? user = AppState.instance.userProfile;
    if (user == null) {
      return false;
    }
    Role userRole = user.defaultRole;
    return userRole == Role.ROLE_ADMINISTRATOR;
  }

  @override
  Widget buildCentralWidget(BuildContext context) {
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
        minHeight: MediaQuery.of(context).size.height - 46,
      ),
      child: Column(
        children: items,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
      ),
    );
  }
}
