import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:yajudge_common/yajudge_common.dart';

import 'utils.dart';
import 'dart:html' as html;

class WebLocalFile extends LocalFile {
  final html.FileReader _reader;

  WebLocalFile(String path, html.FileReader reader) : _reader = reader, super(path);

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

  void saveSettingsValue(String key, String? value) {
    html.Storage storage = html.window.localStorage;
    if (value == null && storage.containsKey(key)) {
      storage.remove(key);
    } else if (value != null) {
      storage[key] = value;
    }
  }

  String? loadSettingsValue(String key) {
    html.Storage storage = html.window.localStorage;
    if (storage.containsKey(key)) {
      return storage[key];
    }
    else {
      return null;
    }
  }

  Uri getWebApiUri(List<String>? arguments) {
    String? savedLocation = loadSettingsValue('api_url');
    if (savedLocation == null) {
      saveSettingsValue('api_url', '');
    }
    if (savedLocation != null && savedLocation.isNotEmpty) {
      return Uri.parse(savedLocation);
    }
    String scheme = Uri.base.scheme;
    String host = Uri.base.host;
    int port = Uri.base.port;
    String path = '/';
    if (host == 'localhost' && port > 10000) {
      // debug run
      return Uri.http('localhost:9081', '/');
    }
    final params = Uri.base.queryParameters;
    if (params.containsKey('api_scheme')) {
      scheme = params['api_scheme']!;
    }
    if (params.containsKey('api_host')) {
      host = params['api_host']!;
    }
    if (params.containsKey('api_port')) {
      port = int.parse(params['api_port']!);
    }
    if (params.containsKey('api_path')) {
      path = params['path']!;
      if (!path.startsWith('/')) {
        path = '/' + path;
      }
    }
    return Uri(scheme: scheme, host: host, port: port, path: path);
  }

  @override
  Future<LocalFile?> pickLocalFileOpen(List<String>? allowedSuffices) {
    html.FileUploadInputElement uploadInput = html.FileUploadInputElement();
    uploadInput.multiple = false;
    StreamController<LocalFile?> streamController = StreamController();
    uploadInput.onChange.listen((event) {
      final List<html.File>? files = uploadInput.files;
      if (files == null || files.length == 0) {
        streamController.add(null);
        return;
      }
      final html.File pickedFile = files[0];
      html.FileReader reader = html.FileReader();
      LocalFile localFile = WebLocalFile(pickedFile.name, reader);
      reader.readAsArrayBuffer(pickedFile);
      streamController.add(localFile);
    });
    uploadInput.click();
    return streamController.stream.first;
  }

  @override
  void saveLocalFile(String suggestName, List<int> data) {
    html.AnchorElement fileDownloadAnchor = html.querySelector("a#file-download-anchor") as html.AnchorElement;
    Uint8List byteArray = Uint8List.fromList(data);
    html.Blob blob = html.Blob([byteArray]);
    fileDownloadAnchor.download = suggestName;
    fileDownloadAnchor.href = html.Url.createObjectUrlFromBlob(blob);
    fileDownloadAnchor.click();
  }

  @override
  Future<LocalFile?> pickLocalFileSave(String suggestName) {
    throw 'Not implemented';
  }

  @override
  Future<CourseContentResponse?> findCachedCourse(String courseId) {
    html.Storage storage = html.window.localStorage;
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
    html.Storage storage = html.window.localStorage;
    var jsonObject = json.encode(courseContent);
    String jsonData = jsonEncode(jsonObject);
    final String key = 'cache/' + courseContent.courseDataId;
    storage[key] = jsonData;
  }

}

PlatformsUtils getPlatformSettings() {
  return WebPlatformUtils();
}