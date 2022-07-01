import 'package:bson/bson.dart';
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

extension TestResultExtension on TestResult {

  BsonObject toBson() {
    Map<String,BsonObject> fields = {};
    fields['target'] = BsonString(target);
    fields['status'] = BsonInt(status.value);
    fields['testNumber'] = BsonInt(testNumber);
    fields['stdout'] = BsonString(stdout);
    fields['stderr'] = BsonString(stderr);
    fields['exitStatus'] = BsonInt(exitStatus);
    fields['signalKilled'] = BsonInt(signalKilled);
    fields['standardMatch'] = BsonBoolean(standardMatch);
    fields['killedByTimer'] = BsonBoolean(killedByTimer);
    fields['valgrindErrors'] = BsonInt(valgrindErrors);
    fields['valgrindOutput'] = BsonString(valgrindOutput);
    fields['checkerOutput'] = BsonString(checkerOutput);
    fields['buildErrorLog'] = BsonString(buildErrorLog);
    return BsonMap(fields);
  }

  static TestResult fromMap(Map<String, dynamic> map) {
    TestResult result = TestResult().deepCopy();
    if (map.containsKey('target')) {
      result.target = map['target'];
    }
    if (map.containsKey('status')) {
      result.status = SolutionStatus.valueOf(map['status']) ?? SolutionStatus.ANY_STATUS_OR_NULL;
    }
    if (map.containsKey('testNumber')) {
      result.testNumber = map['testNumber'];
    }
    if (map.containsKey('stdout')) {
      result.stdout = map['stdout'];
    }
    if (map.containsKey('stderr')) {
      result.stderr = map['stderr'];
    }
    if (map.containsKey('exitStatus')) {
      result.exitStatus = map['exitStatus'];
    }
    if (map.containsKey('signalKilled')) {
      result.signalKilled = map['signalKilled'];
    }
    if (map.containsKey('standardMatch')) {
      result.standardMatch = map['standardMatch'];
    }
    if (map.containsKey('killedByTimer')) {
      result.killedByTimer = map['killedByTimer'];
    }
    if (map.containsKey('valgrindErrors')) {
      result.valgrindErrors = map['valgrindErrors'];
    }
    if (map.containsKey('valgrindOutput')) {
      result.valgrindOutput = map['valgrindOutput'];
    }
    if (map.containsKey('checkerOutput')) {
      result.checkerOutput = map['checkerOutput'];
    }
    if (map.containsKey('buildErrorLog')) {
      result.buildErrorLog = map['buildErrorLog'];
    }
    return result;
  }

  static TestResult fromBson(BsonObject object) {
    if (object is! BsonMap) {
      return TestResult();
    }
    Map<String,dynamic> map = object.value;
    return fromMap(map);
  }

}