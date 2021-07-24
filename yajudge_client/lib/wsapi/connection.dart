import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:json_annotation/json_annotation.dart';
import 'package:archive/archive.dart';


import 'connection_html.dart'
  if (dart.library.io) 'connection_io.dart'
  if (dart.librart.html) 'connection_html.dart';

part 'connection.g.dart';

abstract class AbstractWebSocket {
  bool get connected;
  void send(dynamic data);
}

@JsonSerializable()
class RequestMessage {
  @JsonKey(name: 'id')
  int id = 0;

  @JsonKey(name: 'session')
  String session = '';

  @JsonKey(name: 'service')
  String service = 'unary';

  @JsonKey(name: 'method')
  String method = '';

  @JsonKey(name: 'type')
  String type = '';

  @JsonKey(name: 'argument')
  var argument;

  RequestMessage();
  factory RequestMessage.fromJson(Map<String, dynamic> json) =>
      _$RequestMessageFromJson(json);
  Map<String, dynamic> toJson() => _$RequestMessageToJson(this);
}

@JsonSerializable()
class ResponseError {
  @JsonKey(name: 'code')
  int code = 0;

  @JsonKey(name: 'desc')
  String message = '';

  ResponseError();
  factory ResponseError.fromJson(Map<String, dynamic> json) =>
      _$ResponseErrorFromJson(json);
  Map<String, dynamic> toJson() => _$ResponseErrorToJson(this);

  @override
  String toString() {
    return message;
  }
}

@JsonSerializable()
class ResponseMessage {
  @JsonKey(name: 'id')
  int id = 0;

  @JsonKey(name: 'error')
  ResponseError error = ResponseError();

  @JsonKey(name: 'type')
  String type = '';

  @JsonKey(name: 'result')
  var result;

  ResponseMessage();
  factory ResponseMessage.fromJson(Map<String, dynamic> json) =>
      _$ResponseMessageFromJson(json);
  Map<String, dynamic> toJson() => _$ResponseMessageToJson(this);
}

typedef void ResponseCallback(ResponseMessage responseMessage);

enum RpcConnectionState { NotConnected, Connected }

typedef void RpcConnectionStateChangeCallback(RpcConnectionState state);

class RpcConnection {
  static Duration ReconnectSleep = Duration(seconds: 1);
  static RpcConnection? _instance;

  // WebSocketChannel? _socket;
  AbstractWebSocket? _socket;

  int currentId = 1;
  String _cookie = "";
  String _wsApiUrl;
  RpcConnectionState _state = RpcConnectionState.NotConnected;
  RpcConnectionState getState() => _state;
  RpcConnectionStateChangeCallback? _connectionChangedCallback;
  Map<int, StreamController> _responseControllers = Map();

  RpcConnection(String wsApiUrl) : _wsApiUrl = wsApiUrl {
    _instance = this;
    _reconnect();
    _monitorForRestart();
  }

  void _monitorForRestart() {
    Future.delayed(ReconnectSleep, () {
      if (_state == RpcConnectionState.NotConnected) {
        _reconnect();
      }
      _monitorForRestart();
    });
  }

  static RpcConnection getInstance() {
    if (_instance == null) {
      throw "RpcConnection not created";
    }
    return _instance!;
  }

  void registerChangeStateCallback(RpcConnectionStateChangeCallback? cb) {
    _connectionChangedCallback = cb;
  }

  void _reconnect() {
    _socket = createWebSocket(_wsApiUrl, _processReadyEvent,
        _processErrorEvent, _processDoneEvent, _processMessageEvent);
  }

  void _processRequestMessage(RequestMessage requestMessage) {
    assert (_state == RpcConnectionState.Connected );
    assert (_socket != null && _socket!.connected);
    Map<String, dynamic> jsonMap = requestMessage.toJson();
    String jsonObject = jsonEncode(jsonMap);
    GZipEncoder encoder = GZipEncoder();
    // GZipCodec encoder = GZipCodec(level: ZLibOption.maxLevel);
    List<int> compressedData = encoder.encode(utf8.encode(jsonObject))!;
    // _socket!.send(jsonObject);
    _socket!.send(compressedData);
  }


  void _setConnected(bool conn) {
    if (conn) {
      _state = RpcConnectionState.Connected;
    } else {
      _state = RpcConnectionState.NotConnected;
      _socket = null;
    }
    if (_connectionChangedCallback != null) {
      _connectionChangedCallback!(_state);
    }
    if (conn) {
      assert (_state == RpcConnectionState.Connected);
      assert (_socket != null);
    } else {
      assert (_state == RpcConnectionState.NotConnected);
      assert (_socket == null);
    }
  }

  void setSessionCookie(String value) {
    _cookie = value;
  }

  Future sendUnary(RequestMessage req) {
    if (_state != RpcConnectionState.Connected) {
      return Future.error('Нет соединения с сервером');
    }
    req.id = currentId;
    req.session = _cookie;
    req.type = 'unary';
    currentId++;
    StreamController resp = StreamController();
    _responseControllers[req.id] = resp;
    _processRequestMessage(req);
    Future res = resp.stream.first;
    return res;
  }

  void _processReadyEvent() {
    print('Connection ready');
    _setConnected(true);
  }

  void _processMessageEvent(var rawData) {
    late String data;
    GZipDecoder decoder = GZipDecoder();
    if (rawData.runtimeType==String) {
      data = rawData as String;
    } else if (rawData.runtimeType==ByteBuffer) {
      ByteBuffer binary = rawData as ByteBuffer;
      List<int> uData = decoder.decodeBytes(binary.asUint8List());
      data = utf8.decode(uData);
    } else {
      Uint8List binary = rawData as Uint8List;
      List<int> uData = decoder.decodeBytes(binary);
      data = utf8.decode(uData);
    }
    var rawObj = jsonDecode(data);
    ResponseMessage resp = ResponseMessage.fromJson(rawObj);
    StreamController controller = _responseControllers[resp.id]!;
    if (resp.error.message.isNotEmpty) {
      controller.addError(resp.error);
    } else {
      controller.add(resp.result);
    }
    _responseControllers.remove(resp.id);
  }

  void _processErrorEvent(String data) {
    print('Connection error: ' + data);
    _setConnected(false);
  }

  void _processDoneEvent() {
    print('Connection closed by server');
    _setConnected(false);
  }

}

class ServiceBase {
  RpcConnection _connection;
  String _serviceName;

  ServiceBase(String serviceName, RpcConnection connection)
      : _connection = connection,
        _serviceName = serviceName {}

  void setSessionCookie(String cookie) {
    _connection.setSessionCookie(cookie);
  }

  Future callUnaryMethod(String methodName, var argument) async {
    RequestMessage requestMessage = new RequestMessage();
    requestMessage.service = _serviceName;
    requestMessage.method = methodName;
    requestMessage.type = 'unary';
    requestMessage.argument = argument;
    Future respFuture = _connection.sendUnary(requestMessage);
    Future result = respFuture;
    return result;
  }
}
