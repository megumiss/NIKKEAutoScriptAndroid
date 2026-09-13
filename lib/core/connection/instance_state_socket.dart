import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class InstanceStateEvent {
  const InstanceStateEvent({required this.name, required this.state});

  factory InstanceStateEvent.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    final name = json['name'];
    final state = json['state'];
    if (type != 'state' || name is! String || state is! int) {
      throw const FormatException('无效的实例状态事件');
    }
    return InstanceStateEvent(name: name, state: state);
  }

  final String name;
  final int state;
}

class InstanceStateSocket {
  InstanceStateSocket({required this.uri});

  final Uri uri;
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;

  Future<void> connect({
    required void Function(InstanceStateEvent event) onState,
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
            onState(InstanceStateEvent.fromJson(decoded));
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
