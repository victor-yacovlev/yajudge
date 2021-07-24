import 'connection.dart';
import 'dart:io';

class NativeWebSocket extends AbstractWebSocket {
  final String _url;
  WebSocket? _webSocket;
  String? _error;
  Function _onReady;
  Function (String) _onError;
  Function _onClosed;
  Function (dynamic) _onMessage;

  bool get connected {
    return _webSocket != null && _webSocket!.readyState == WebSocket.open;
  }

  void send(dynamic data) {
    assert (connected);
    _webSocket!.add(data);
  }

  NativeWebSocket(String url, Function onReady,
      Function (String) onError, Function onClosed, Function (dynamic) onMessage)
      : _url = url, _onReady = onReady, _onError = onError,
        _onClosed = onClosed, _onMessage = onMessage
  {
    WebSocket.connect(url).then((WebSocket webSocket) {
      _webSocket = webSocket;
      assert (connected);
      _webSocket!.listen(
        (var event) {
          _onMessage(event);
        },
        onDone: () {
          _onClosed();
        },
        onError: (var err) {
          _onError(err.toString());
        },
        cancelOnError: true
      );
      _onReady();
    }).onError((error, stackTrace) {
      _error = error.toString();
      _onError(_error!);
    });
  }

}

AbstractWebSocket createWebSocket(
    String url,
    Function onReady,
    Function (String) onError,
    Function onClosed,
    Function (dynamic) onMessage
    )
{
  return NativeWebSocket(url, onReady, onError, onClosed, onMessage);
}