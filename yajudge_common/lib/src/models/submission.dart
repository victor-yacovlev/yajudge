import 'package:fixnum/fixnum.dart';

import '../../yajudge_common.dart';

extension SubmissionExtension on Submission {
  SubmissionListEntry asSubmissionListEntry() {
    return SubmissionListEntry(
      submissionId: id,
      status: status,
      gradingStatus: gradingStatus,
      sender: user,
      timestamp: timestamp,
      problemId: problemId,
    );
  }

  void updateId(int newId) {
    id = Int64(newId);
  }
}