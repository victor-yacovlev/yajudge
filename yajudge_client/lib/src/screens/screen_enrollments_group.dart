import 'package:flutter/material.dart';
import 'package:yajudge_common/yajudge_common.dart';
import '../controllers/connection_controller.dart';
import 'screen_base.dart';

class EnrollmentsGroupScreen extends BaseScreen {
  final String courseUrlPrefix;
  final String groupName;
  EnrollmentsGroupScreen({
    required User loggedUser,
    required this.courseUrlPrefix,
    required this.groupName,
  }) : super(loggedUser: loggedUser);

  @override
  State<StatefulWidget> createState() => EnrollmentsGroupScreenState(title: 'Группа $groupName');

}

class EnrollmentsGroupScreenState extends BaseScreenState {

  GroupEnrollments? _data;

  EnrollmentsGroupScreenState({required String title}) : super(title: title);

  @override
  void initState() {
    final urlPrefix = (widget as EnrollmentsGroupScreen).courseUrlPrefix;
    final groupName = (widget as EnrollmentsGroupScreen).groupName;
    super.initState();
    final request = GroupEnrollmentsRequest(
      course: Course(urlPrefix: urlPrefix),
      groupPattern: groupName,
    );
    final service = ConnectionController.instance!.coursesService;
    final futureResult = service.getGroupEnrollments(request);

  }

  void setResponseFromServer(GroupEnrollments data) {
    setState(() {
      _data = data;
    });
  }

  @override
  Widget buildCentralWidget(BuildContext context) {
    List<Widget> items = [];
    items.add(Text('Редактирование группы пока не реализовано'));
    return Container(
      padding: EdgeInsets.all(20),
      child: Column(
        children: items,
      ),
    );
  }


}