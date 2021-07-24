import 'dart:typed_data';

import 'package:json_annotation/json_annotation.dart';
import '../wsapi/courses.dart';

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
  bool isAppleLAF() => throw 'Not implemented';
  void saveSettingsValue(String key, String? value) => throw 'Not implemented';
  String? loadSettingsValue(String key) => throw 'Not implemented';
  String? getWsApiUrl() => throw 'Not implemented';

  Future<LocalFile?> pickLocalFileOpen(List<String>? allowedSuffices) => throw 'Not implemented';

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

  String? _overrideTheme;
  set overrideTheme (String? value ){
    if (value == null) {
      _overrideTheme = null;
      return;
    }
    value = value.toLowerCase();
    if (value != 'cupertino' && value != 'material') {
      throw 'Not valid theme, must be one of "Cupertino" or "Material"';
    }
    _overrideTheme = value;
  }

  bool get isCupertino {
    if (_overrideTheme != null) {
      return _overrideTheme == 'cupertino';
    } else {
      return isAppleLAF();
    }
  }

}

