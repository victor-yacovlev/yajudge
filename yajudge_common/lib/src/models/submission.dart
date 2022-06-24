import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart';

import '../../yajudge_common.dart';

extension SubmissionExtension on Submission {
  SubmissionListEntry asSubmissionListEntry() {
    return SubmissionListEntry(
      submissionId: id,
      status: status,
      gradingStatus: gradingStatus,
      sender: user,
      datetime: datetime,
      problemId: problemId,
    ).deepCopy();
  }

  void updateId(int newId) {
    id = Int64(newId);
  }
}