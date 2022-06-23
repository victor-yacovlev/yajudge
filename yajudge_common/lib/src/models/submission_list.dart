import '../../yajudge_common.dart';

extension SubmissionListEntryExtension on SubmissionListEntry {
  void updateStatus(SolutionStatus newStatus) {
    status = newStatus;
  }
}

extension SubmissionListQueryExtension on SubmissionListQuery {
  bool match(Submission submission, User currentUser) {
    if (submissionId!=0 && submissionId==submission.id) {
      return true;
    }
    bool statusMatch = true;
    if (statusFilter != SolutionStatus.ANY_STATUS_OR_NULL) {
      statusMatch = submission.status==statusFilter;
    }

    bool currentUserMatch = currentUser.id==submission.user.id;
    bool hideThisSubmission = false;
    if (currentUserMatch) {
      hideThisSubmission = !showMineSubmissions;
    }

    bool problemMatch = true;
    if (problemIdFilter.isNotEmpty) {
      problemMatch = problemIdFilter==submission.problemId;
    }
    bool nameMatch = true;
    if (nameQuery.trim().isNotEmpty) {
      final normalizedName = nameQuery.trim().toUpperCase().replaceAll(r'\s+', ' ');
      final user = submission.user;
      bool firstNameLike = user.firstName.toUpperCase().startsWith(normalizedName);
      bool lastNameLike = user.firstName.toUpperCase().startsWith(normalizedName);
      final firstLastName = '${user.firstName} ${user.lastName}'.toUpperCase();
      final lastFirstName = '${user.lastName} ${user.firstName}'.toUpperCase();
      bool firstLastNameLike = firstLastName.startsWith(normalizedName);
      bool lastFirstNameLike = lastFirstName.startsWith(normalizedName);
      nameMatch = firstNameLike || lastNameLike || lastFirstNameLike || firstLastNameLike;
    }
    return statusMatch && problemMatch && nameMatch && !hideThisSubmission;
  }
}