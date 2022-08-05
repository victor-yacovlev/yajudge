import 'package:yajudge_common/yajudge_common.dart';
import 'package:flutter/material.dart';
import '../controllers/connection_controller.dart';
import '../widgets/unified_widgets.dart';
import 'screen_base.dart';

class EnrollmentsScreen extends BaseScreen {
  final String courseUrlPrefix;
  EnrollmentsScreen({required User loggedUser, required this.courseUrlPrefix}) : super(loggedUser: loggedUser);

  @override
  State<StatefulWidget> createState() => EnrollmentsScreenState(title: 'Группы курса');

}

class EnrollmentsScreenState extends BaseScreenState {

  AllGroupsEnrollmentsResponse? _allGroups;

  EnrollmentsScreenState({required String title}) : super(title: title);

  @override
  void initState() {
    super.initState();
    final service = ConnectionController.instance!.enrollmentsService;
    final urlPrefix = (widget as EnrollmentsScreen).courseUrlPrefix;
    final futureResult = service.getAllGroupsEnrollments(Course(urlPrefix: urlPrefix));
    futureResult.then(setResponseFromServer);
  }

  void setResponseFromServer(AllGroupsEnrollmentsResponse response) {
    setState(() {
      _allGroups = response;
      title = 'Группы курса ${response.course.name}';
    });
  }

  @override
  Widget buildCentralWidget(BuildContext context) {
    List<Widget> items = [];
    if (_allGroups == null) {
      items.add(Text('Загружается...'));
    }
    else {
      for (final group in _allGroups!.groups) {
        items.add(buildGroupWidget(context, group));
      }
    }
    return Container(
      padding: EdgeInsets.all(20),
      child: Column(
        children: items,
      ),
    );
  }

  Widget buildGroupWidget(BuildContext context, GroupEnrollmentsResponse group) {
    final courseUrlPrefix = (widget as EnrollmentsScreen).courseUrlPrefix;
    final groupName = group.groupPattern;
    final action = () {
      Navigator.pushNamed(context, '/enrollments/$courseUrlPrefix/$groupName');
    };
    final nameToString = (User user) {
      String result = user.lastName;
      if (user.firstName.isNotEmpty) {
        if (result.isNotEmpty) result += ' ';
        result += user.firstName;
      }
      if (user.midName.isNotEmpty) {
        if (result.isNotEmpty) result += ' ';
        result += user.midName;
      }
      return result;
    };
    final namesToString = (List<User> users) {
      if (users.isEmpty) {
        return 'Нет';
      }
      else {
        String result = '';
        for (final user in users) {
          if (result.isNotEmpty) {
            result += ', ';
          }
          result += nameToString(user);
        }
        return result;
      }
    };
    final teachers = namesToString(group.teachers);
    final assistants = namesToString(group.assistants);
    int groupSize = group.groupStudents.length;
    int foreignSize = group.foreignStudents.length;
    final groupInfo = [
      'Семинарист: $teachers',
      'Учебный ассистент: $assistants',
      'Студентов в группе: $groupSize',
      'Студентов из других групп: $foreignSize'
    ];
    final groupInfoText = groupInfo.join('\n');
    final card = YCardLikeButton('Группа $groupName', action, subtitle: groupInfoText);
    return card;
  }

}