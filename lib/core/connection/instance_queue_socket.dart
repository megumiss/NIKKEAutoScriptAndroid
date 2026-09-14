import 'dart:async';
import 'dart:convert';
import 'package:nkas_mobile/core/connection/authenticated_socket.dart';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:nkas_mobile/core/api/queue_info.dart';

class InstanceQueueEvent {
  const InstanceQueueEvent({required this.name, required this.queue});

  factory InstanceQueueEvent.fromJson(Map<String, dynamic> json) {
    if (json['type'] != 'queue' || json['name'] is! String) {
      throw const FormatException('无效的实例队列事件');
    }
    return InstanceQueueEvent(
      name: json['name'] as String,
      queue: QueueInfo.fromJson(json),
    );
  }

  final String name;
  final QueueInfo queue;
}

class InstanceQueueSocket {
  InstanceQueueSocket({
    required this.uri,
    this.headers = const {},
    this.onDisconnected,
  });

  final Uri uri;
  final Map<String, String> headers;
  final void Function()? onDisconnected;
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;

  Future<void> connect({
    required void Function(InstanceQueueEvent event) onQueue,
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
      return;
    }
    _subscription = channel.stream.listen(
      (message) {
        try {
          final decoded = jsonDecode(message.toString());
          if (decoded is Map<String, dynamic>) {
            onQueue(InstanceQueueEvent.fromJson(decoded));
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
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }
}
