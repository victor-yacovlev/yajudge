// ignore_for_file: unused_element

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
    bool isAdministrator = widget.loggedUser.defaultRole==Role.ROLE_ADMINISTRATOR;
    Text title = Text(
      isAdministrator ? 'Все курсы' : 'Мои курсы',
      style: Theme.of(context).textTheme.headline6,
    );
    result.add(Padding(child: title, padding: EdgeInsets.fromLTRB(0, 30, 0, 20)));

    for (final e in courses) {
      String title = e.course.name;
      void progressAction() {
        Navigator.pushNamed(context, '/progress/${e.course.urlPrefix}');
      }
      void submissionsAction() {
        Navigator.pushNamed(context, '/submissions/${e.course.urlPrefix}');
      }
      void enrollmentsAction() {
        Navigator.pushNamed(context, '/enrollments/${e.course.urlPrefix}');
      }
      void settingsAction() {
        Navigator.pushNamed(context, '/courses/${e.course.urlPrefix}');
      }
      String? roleTitle;
      List<Widget> subactions = [];
      if (e.role != Role.ROLE_STUDENT || isAdministrator) {
        roleTitle = 'Вид глазами студента';
        subactions.addAll([
          IconButton(
            icon: const Icon(Icons.sort),
            color: Theme.of(context).textTheme.bodyText1!.color!.withAlpha(100),
            onPressed: progressAction,
            tooltip: 'Прогресс',
          ),
          IconButton(
            icon: const Icon(Icons.view_list_outlined),
            color: Theme.of(context).textTheme.bodyText1!.color!.withAlpha(100),
            onPressed: submissionsAction,
            tooltip: 'Посылки',
          ),
        ]);
      }
      if (e.role == Role.ROLE_LECTURER || e.role == Role.ROLE_ADMINISTRATOR || isAdministrator) {
        subactions.add(
            IconButton(
              icon: const Icon(Icons.people),
              color: Theme.of(context).textTheme.bodyText1!.color!.withAlpha(100),
              onPressed: enrollmentsAction,
              tooltip: 'Группы и студенты',
            )
        );
        // subactions.add(
        //   IconButton(
        //     icon: const Icon(Icons.settings),
        //     color: Theme.of(context).textTheme.bodyText1!.color!.withAlpha(100),
        //     onPressed: settingsAction,
        //     tooltip: 'Настройки курса',
        //   )
        // );
      }
      String link = '/${e.course.urlPrefix}/';
      void action() {
        Navigator.pushNamed(context, link);
      }
      YCardLikeButton button = YCardLikeButton(title, action, subtitle: roleTitle, subactions: subactions);
      final buttonWrapper = Padding(
        child: button,
        padding: EdgeInsets.fromLTRB(0, 0, 0, 16),
      );
      result.add(buttonWrapper);
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
      void action() {
        Navigator.pushNamed(context, link);
      }
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
