import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:yajudge_client/wsapi/courses.dart';

import 'utils.dart';
import 'dart:html';

class WebLocalFile extends LocalFile {
  final FileReader _reader;

  WebLocalFile(String path, FileReader reader) : _reader = reader, super(path);

  @override
  Future<Uint8List> readContents() {
    StreamController<Uint8List> streamController = StreamController();
    _reader.onLoadEnd.listen((event) {
      Object? readerResult = _reader.result;
      if (readerResult == null) {
        streamController.addError('Empty read result');
      } else {
        Uint8List result = readerResult as Uint8List;
        streamController.add(result);
      }
    });
    return streamController.stream.first;
  }
}

class WebPlatformUtils extends PlatformsUtils {

  WebPlatformUtils() : super() {
    setUrlStrategy(PathUrlStrategy());
  }

  @override
  bool isNativeApp() => false;

  @override
  bool isAppleLAF() {
    Navigator navigator = window.navigator;
    String userAgent = navigator.userAgent;
    String vendor = navigator.vendor;
    bool isWebKit = userAgent.contains('WebKit');
    bool isAppleVendor = vendor.contains('Apple');
    return isWebKit && isAppleVendor;
  }

  void saveSettingsValue(String key, String? value) {
    Storage storage = window.localStorage;
    if (value == null && storage.containsKey(key)) {
      storage.remove(key);
    } else if (value != null) {
      storage[key] = value;
    }
  }

  String? loadSettingsValue(String key) {
    Storage storage = window.localStorage;
    if (storage.containsKey(key)) {
      return storage[key];
    }
    else {
      return null;
    }
  }

  String? getWsApiUrl() {
    String? wsApiUrl;
    String wsProtocol = 'ws';
    if (Uri.base.queryParameters.containsKey('wsApi')) {
      wsApiUrl = Uri.base.queryParameters['wsApi']!;
    } else if (Uri.base.host == 'localhost' && Uri.base.port > 10000) {
      // debug run
      wsApiUrl = "localhost:8080/api-ws";
    } else {
      wsApiUrl = Uri.base.host + ':' + Uri.base.port.toString() + '/api-ws';
    }
    if (Uri.base.scheme == 'https') {
      wsProtocol = 'wss';
    }
    if (wsApiUrl == null) {
      return null;
    } else {
      return wsProtocol + '://' + wsApiUrl;
    }
  }

  @override
  Future<LocalFile?> pickLocalFileOpen(List<String>? allowedSuffices) {
    FileUploadInputElement uploadInput = FileUploadInputElement();
    uploadInput.multiple = false;
    StreamController<LocalFile?> streamController = StreamController();
    uploadInput.onChange.listen((event) {
      final List<File>? files = uploadInput.files;
      if (files == null || files.length == 0) {
        streamController.add(null);
        return;
      }
      final File pickedFile = files[0];
      FileReader reader = FileReader();
      LocalFile localFile = WebLocalFile(pickedFile.name, reader);
      reader.readAsArrayBuffer(pickedFile);
      streamController.add(localFile);
    });
    uploadInput.click();
    return streamController.stream.first;
  }

  @override
  Future<CourseContentResponse?> findCachedCourse(String courseId) {
    Storage storage = window.localStorage;
    final String key = 'cache/' + courseId;
    CourseContentResponse? result;
    if (storage.containsKey(key)) {
      String jsonData = storage[key]!;
      var jsonObject = jsonDecode(jsonData);
      result = CourseContentResponse.fromJson(jsonObject);
    } else {
      result = null;
    }
    return Future.value(result);
  }

  @override
  void storeCourseInCache(CourseContentResponse courseContent) {
    Storage storage = window.localStorage;
    var jsonObject = courseContent.toJson();
    String jsonData = jsonEncode(jsonObject);
    final String key = 'cache/' + courseContent.courseDataId;
    storage[key] = jsonData;
  }

}

PlatformsUtils getPlatformSettings() {
  return WebPlatformUtils();
}