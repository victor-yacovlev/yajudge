import 'package:protobuf/protobuf.dart';

import '../../yajudge_common.dart';

extension SubmissionListEntryExtension on SubmissionListEntry {
  void updateGradingStatus(SolutionStatus newStatus, SubmissionProcessStatus newGradingStatus) {
    status = newStatus;
    gradingStatus = newGradingStatus;
  }
}

extension SubmissionListResponseExtension on SubmissionListResponse {

  SubmissionListResponse mergeWith(SubmissionListResponse other) {
    if (!query.equals(other.query)) {
      return other.deepCopy();
    }
    if (other.query.offset == 0) {
      return other.deepCopy();
    }
    final newResponse = deepCopy();
    newResponse.entries.addAll(other.entries);
    newResponse.totalCount = other.totalCount;
    return newResponse;
  }

  void updateEntry(SubmissionListEntry newEntry) {
    bool found = false;
    for (var entry in entries) {
      if (entry.submissionId == newEntry.submissionId) {
        entry.updateGradingStatus(newEntry.status, newEntry.gradingStatus);
        found = true;
        break;
      }
    }
    if (!found) {
      final sender = newEntry.sender;
      String fullName = '${sender.firstName} ${sender.lastName} ${sender.midName}';
      fullName = fullName.trim();
      if (fullName.isNotEmpty) {
        entries.add(newEntry);
        entries.sort((a,b) => a.submissionId.compareTo(b.submissionId));
      }
    }
  }

  bool get hasMoreItems {
    return totalCount > entries.length;
  }

  bool get isEmpty {
    return entries.isEmpty;
  }

}

extension SubmissionListQueryExtension on SubmissionListQuery {

  bool equals(SubmissionListQuery other) {
    bool nameMatch = nameQuery.trim() == other.nameQuery.trim();
    bool problemMatch = problemIdFilter.trim() == other.problemIdFilter.trim();
    bool courseMatch = courseId == other.courseId;
    bool submissionMatch = submissionId == other.submissionId;
    bool statusMatch = statusFilter == other.statusFilter;
    bool showMineMatch = showMineSubmissions == other.showMineSubmissions;
    return nameMatch && problemMatch && courseMatch && submissionMatch && statusMatch && showMineMatch;
  }

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

extension SubmissionListNotificationsRequestExtension on SubmissionListNotificationsRequest {
  bool match(Submission submission, User currentUser) {
    if (submissionIds.contains(submission.id)) {
      return true;
    }
    else {
      return filterRequest.match(submission, currentUser);
    }
  }
}