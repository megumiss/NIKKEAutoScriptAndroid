import 'package:web_socket_channel/web_socket_channel.dart';

// Browser builds use the HttpOnly same-origin entry cookie; web browsers
// cannot add an Authorization header to a WebSocket handshake.
WebSocketChannel authenticatedSocket(Uri uri, Map<String, String> headers) =>
    WebSocketChannel.connect(uri);
