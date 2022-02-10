import 'screen_base.dart';
import '../widgets/unified_widgets.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:flutter/material.dart';

class DashboardScreen extends BaseScreen {

  final CoursesList coursesList;

  DashboardScreen({
    required User user,
    required this.coursesList,
  }): super(loggedUser: user) {
    print('Logged as user(id=${user.id}), showing Dashboard');
  }

  @override
  State<StatefulWidget> createState() => DashboardScreenState();
}


class DashboardScreenState extends BaseScreenState {

  DashboardScreenState() : super(title: 'Главная');

  List<Widget> _createMyCourses() {
    final courses = (widget as DashboardScreen).coursesList.courses;
    if (courses.isEmpty) {
      return [];
    }
    List<Widget> result = [];
    Text title = Text(
      'Мои курсы',
      style: Theme.of(context).textTheme.headline6,
    );
    result.add(Padding(child: title, padding: EdgeInsets.fromLTRB(0, 30, 0, 20)));
    for (final e in courses) {
      String title = e.course.name;
      String? roleTitle;
      if (e.role != Role.ROLE_STUDENT) {
        roleTitle = 'Вид глазами студента';
      }
      String link = '/' + e.course.urlPrefix + '/';
      VoidCallback action = () {
        Navigator.pushNamed(context, link);
      };
      YCardLikeButton button = YCardLikeButton(title, action, subtitle: roleTitle);
      result.add(button);
    }
    return result;
  }

  List<Widget> _createAdminEntries() {
    if (widget.loggedUser.defaultRole != Role.ROLE_ADMINISTRATOR) {
      return [];
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
        minHeight: MediaQuery.of(context).size.height - 70,
      ),
      child: Column(
        children: items,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
      ),
    );
  }
}
