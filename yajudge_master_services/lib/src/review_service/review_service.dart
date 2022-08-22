import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart';

import '../service_call_extension.dart';


class CodeReviewManagementService extends CodeReviewManagementServiceBase {
  final log = Logger('CodeReviewManagement');
  final PostgreSQLConnection connection;
  final SubmissionManagementClient submissionManager;
  final UserManagementClient userManager;
  final String secretKey;

  CodeReviewManagementService({
    required this.connection,
    required this.submissionManager,
    required this.userManager,
    required this.secretKey,
  });

  @override
  Future<CodeReview> applyCodeReview(ServiceCall call, CodeReview request) async {
    CodeReview review = request.deepCopy();
    CodeReview? existingReview = await _getCodeReviewForSubmission(call, request.submissionId.toInt());
    bool updateReview = false;
    if (existingReview!=null) {
      updateReview = true;
      bool sameReview = existingReview.contentEqualsTo(review);
      if (sameReview) {
        await submissionManager.updateSubmissionStatus(
          Submission(id: review.submissionId, status: review.newStatus),
          options: CallOptions(metadata: call.clientMetadata),
        );
        return request;
      }
    }
    if (call.getSessionUser(secretKey) == null) {
      throw GrpcError.permissionDenied('must be logged as teacher to apply review');
    }
    review.author = call.getSessionUser(secretKey)!;
    DateTime reviewDateTime = DateTime.now().toUtc();
    review.datetime = Int64(reviewDateTime.millisecondsSinceEpoch ~/ 1000);
    if (!updateReview) {
      // create new review
      final query = '''
      insert into code_reviews(submissions_id,author_id,global_comment,datetime)
      values (@submissions_id,@author_id,@global_comment,@datetime)
      returning id
      ''';
      final rows = await connection.query(query, substitutionValues: {
        'submissions_id': review.submissionId.toInt(),
        'author_id': review.author.id.toInt(),
        'global_comment': review.globalComment,
        'datetime': reviewDateTime,
      });
      final idRow = rows.single;
      final idValue = idRow.single as int;
      review.id = Int64(idValue);
      await _addLineComments(review.lineComments, review.id);
    }
    else {
      // update existing review, but drop related line comments before
      final deleteQuery = '''
      delete from review_line_comments where code_reviews_id=@id
      ''';
      await connection.query(deleteQuery, substitutionValues: {'id': existingReview!.id.toInt()});
      final updateQuery = '''
      update code_reviews
      set
        author_id=@author_id,
        global_comment=@global_comment,
        datetime=@datetime
      where
        id=@id
      ''';
      await connection.query(updateQuery, substitutionValues: {
        'author_id': review.author.id.toInt(),
        'global_comment': review.globalComment,
        'datetime': DateTime.fromMillisecondsSinceEpoch(review.datetime.toInt() * 1000, isUtc: true),
        'id': existingReview.id.toInt(),
      });
      await _addLineComments(review.lineComments, existingReview.id);
    }
    await submissionManager.updateSubmissionStatus(
      Submission(id: review.submissionId, status: review.newStatus),
      options: CallOptions(metadata: call.clientMetadata),
    );
    return review;
  }

  @override
  Future<ReviewHistory> getReviewHistory(ServiceCall call, Submission request) async {
    final submission = await submissionManager.getSubmissionResult(request,
      options: CallOptions(metadata: call.clientMetadata),
    );
    final problemId = submission.problemId;
    final maxDateTime = DateTime.fromMillisecondsSinceEpoch(
        submission.datetime.toInt() * 1000, isUtc: false
    );
    final userId = submission.user.id;
    final courseId = submission.course.id;
    final query = '''
    select id from submissions
    where 
      courses_id=@courseId and
      problem_id=@problemId and
      users_id=@userId and
      datetime<=@maxDateTime
    ''';
    final rows = await connection.query(query, substitutionValues: {
      'courseId': courseId.toInt(),
      'problemId': problemId,
      'userId': userId.toInt(),
      'maxDateTime': maxDateTime,
    });
    final ids = rows.map<int>((e) => e[0] as int);
    List<CodeReview> reviews = [];
    for (final id in ids) {
      CodeReview? review = await _getCodeReviewForSubmission(call, id);
      if (review != null) {
        reviews.add(review);
      }
    }
    final result = ReviewHistory(reviews: reviews);
    log.fine('sent review history of size ${result.reviews.length} on submission ${request.id}');
    return result;
  }

  Future<CodeReview?> _getCodeReviewForSubmission(ServiceCall call, int submissionId) async {
    final query = '''
    select id, author_id, global_comment, datetime
    from code_reviews
    where submissions_id=@id
    ''';
    final rows = await connection.query(query, substitutionValues: {'id': submissionId});
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.single;
    final id = row[0] as int;
    final authorId = row[1] as int;
    final globalComment = row[2] is String? row[2] as String : '';
    final datetime = row[3] as DateTime;
    final author = await userManager.getProfileById(
      User(id: Int64(authorId)),
      options: CallOptions(metadata: call.clientMetadata)
    );
    author.password = '';
    final lineComments = await _getLineComments(Int64(id));
    final result = CodeReview(
      id: Int64(id),
      submissionId: Int64(submissionId),
      author: author,
      globalComment: globalComment,
      datetime: Int64(datetime.millisecondsSinceEpoch ~/ 1000),
      lineComments: lineComments,
    );
    return result;
  }

  Future<List<LineComment>> _getLineComments(Int64 id) async {
    List<LineComment> result = [];
    final query = '''
    select line_number, message, context, file_name 
    from review_line_comments
    where code_reviews_id=@id
    ''';
    final rows = await connection.query(query, substitutionValues: {'id': id.toInt()});
    for (final row in rows) {
      final lineNumber = row[0] as int;
      final message = row[1] as String;
      final context = row[2] is String? row[2] as String : '';
      final fileName = row[3] as String;
      result.add(LineComment(
        lineNumber: lineNumber,
        message: message,
        context: context,
        fileName: fileName,
      ));
    }
    return result;
  }

  Future<void> _addLineComments(List<LineComment> comments, Int64 reviewId) async {
    final query = '''
    insert into review_line_comments(code_reviews_id,line_number,message,context,file_name)
    values (@id,@line,@message,@context,@file)
    ''';
    for (final comment in comments) {
      await connection.query(query, substitutionValues: {
        'id': reviewId.toInt(),
        'line': comment.lineNumber,
        'message': comment.message,
        'context': comment.context,
        'file': comment.fileName,
      });
    }
  }


}