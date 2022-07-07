import '../../yajudge_common.dart';

extension LineRangeExtension on LineRange {
  int get length {
    return end - start + 1;
  }
}

extension DiffOperationExtension on DiffOperation {

}