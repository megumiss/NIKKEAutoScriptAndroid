import 'dart:async';
import 'dart:convert';
import 'package:nkas_mobile/core/connection/authenticated_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class InstanceLogEvent {
  const InstanceLogEvent({required this.html});

  factory InstanceLogEvent.fromJson(Map<String, dynamic> json) {
    if (json['type'] != 'log') {
      throw const FormatException('无效的实例日志事件');
    }
    final raw = json['html'];
    final html = raw is List
        ? raw.whereType<String>().toList(growable: false)
        : raw is String
        ? [raw]
        : const <String>[];
    return InstanceLogEvent(html: html);
  }

  final List<String> html;
}

class InstanceLogSocket {
  InstanceLogSocket({
    required this.uri,
    this.headers = const {},
    this.onDisconnected,
  });

  final Uri uri;
  final Map<String, String> headers;
  final void Function()? onDisconnected;
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;

  Future<bool> connect({
    required void Function(InstanceLogEvent event) onLog,
    void Function(Object error)? onError,
    void Function()? onClosed,
  }) async {
    await close();
    final channel = authenticatedSocket(uri, headers);
    _channel = channel;
    try {
      await channel.ready;
    } catch (error) {
      onDisconnected?.call();
      await close();
      onError?.call(error);
      return false;
    }
    _subscription = channel.stream.listen(
      (message) {
        try {
          final decoded = jsonDecode(message.toString());
          if (decoded is Map<String, dynamic>) {
            onLog(InstanceLogEvent.fromJson(decoded));
          }
        } catch (error) {
          onError?.call(error);
        }
      },
      onError: (Object error) {
        onDisconnected?.call();
        onError?.call(error);
      },
      onDone: () {
        onDisconnected?.call();
        onClosed?.call();
      },
    );
    return true;
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }
}
