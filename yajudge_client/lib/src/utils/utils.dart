import 'dart:typed_data';

import 'package:yajudge_common/yajudge_common.dart';

import 'utils_html.dart'
  if (dart.library.io) 'utils_io.dart'
  if (dart.librart.html) 'utils_html.dart';

abstract class LocalFile {
  String path;
  LocalFile(String path) : this.path = path;
  Future<Uint8List> readContents() => throw 'Not implemented';
}


abstract class PlatformsUtils {
  bool disableCoursesCache = false;

  bool isNativeApp() => throw 'Not implemented';
  bool isWebApp() => !isNativeApp();

  void saveSettingsValue(String key, String? value) => throw 'Not implemented';
  String? loadSettingsValue(String key) => throw 'Not implemented';
  Uri getGrpcApiUri(List<String>? arguments) => Uri();
  Uri getWebApiUri(List<String>? arguments) => Uri();

  Future<LocalFile?> pickLocalFileOpen(List<String>? allowedSuffices) => throw 'Not implemented';
  void saveLocalFile(String suggestName, List<int> data) => throw 'Not implemented';

  Future<CourseContentResponse?> findCachedCourse(String courseId) => throw 'Not implemented';
  void storeCourseInCache(CourseContentResponse courseContent) => throw 'Not implemented';

  static PlatformsUtils? _instance;

  PlatformsUtils();

  factory PlatformsUtils.getInstance() {
    if (_instance == null) {
      _instance = getPlatformSettings();
    }
    return _instance!;
  }

}

