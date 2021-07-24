import 'connection.dart';
import 'dart:html';

class BrowserWebSocket extends AbstractWebSocket {
  final String _url;
  WebSocket? _webSocket;
  String? _error;
  Function _onReady;
  Function (String) _onError;
  Function _onClosed;
  Function (dynamic) _onMessage;

  bool get connected {
    return _webSocket != null && _webSocket!.readyState == WebSocket.OPEN;
  }

  void send(dynamic data) {
    assert (connected);
    _webSocket!.send(data);
  }

  BrowserWebSocket(String url, Function onReady,
      Function (String) onError, Function onClosed, Function (dynamic) onMessage)
      : _url = url, _onReady = onReady, _onError = onError,
        _onClosed = onClosed, _onMessage = onMessage
  {
    _webSocket = WebSocket(url);
    _webSocket!.binaryType = "arraybuffer";
    _webSocket!.onOpen.listen((event) => _onReady());
    _webSocket!.onMessage.listen((event) => _onMessage(event.data));
    _webSocket!.onClose.listen((event) => _onClosed());
    _webSocket!.onError.listen((event) => _onError(event.toString()));
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
  return BrowserWebSocket(url, onReady, onError, onClosed, onMessage);
}