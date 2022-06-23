import 'package:fixnum/fixnum.dart';

import '../../yajudge_common.dart';

extension ReviewHistoryExtension on ReviewHistory {
  CodeReview? findBySubmissionId(Int64 submissionId) {
    for (final review in reviews) {
      if (review.submissionId == submissionId) {
        return review;
      }
    }
    return null;
  }
}

extension CodeReviewExtension on CodeReview {

  String debugInfo() {
    final lineMessages = lineComments.map((e) => '${e.lineNumber+1}: "${e.message}"');
    return '{ "$globalComment", [${lineMessages.join(', ')}]';
  }

  bool get contentIsEmpty {
    bool globalCommentIsEmpty = globalComment.trim().isEmpty;
    bool linesEmpty = lineComments.isEmpty;
    return globalCommentIsEmpty && linesEmpty;
  }

  bool get contentIsNotEmpty => !contentIsEmpty;

  bool contentEqualsTo(CodeReview other) {
    final myGlobalComment = globalComment.trim();
    final otherGlobalComment = other.globalComment.trim();
    final myLineComments = lineComments;
    final otherLineComments = other.lineComments;
    if (myGlobalComment != otherGlobalComment) {
      return false;
    }
    if (myLineComments.length != otherLineComments.length) {
      return false;
    }
    for (final myComment in myLineComments) {
      LineComment? matchingOtherComment;
      for (final otherComment in otherLineComments) {
        if (otherComment.fileName==myComment.fileName && otherComment.lineNumber==myComment.lineNumber) {
          matchingOtherComment = otherComment;
          break;
        }
      }
      if (matchingOtherComment == null) {
        return false;
      }
      if (matchingOtherComment.message.trim() != myComment.message.trim()) {
        return false;
      }
    }
    return true;
  }
}