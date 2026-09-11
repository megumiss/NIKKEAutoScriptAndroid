import 'dart:async';
import 'dart:convert';
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
  InstanceLogSocket({required this.uri});

  final Uri uri;
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;

  Future<void> connect({
    required void Function(InstanceLogEvent event) onLog,
    void Function(Object error)? onError,
    void Function()? onClosed,
  }) async {
    await close();
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    try {
      await channel.ready;
    } catch (error) {
      await close();
      onError?.call(error);
      return;
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
      onError: onError,
      onDone: onClosed,
    );
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }
}
