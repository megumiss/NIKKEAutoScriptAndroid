import 'package:flutter/widgets.dart';
import 'package:nkas_mobile/core/connection/connection_controller.dart';

class BackendAuthScope extends InheritedNotifier<ConnectionController> {
  const BackendAuthScope({
    required ConnectionController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static ConnectionController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BackendAuthScope>()?.notifier;

  static Map<String, String> headersFor(BuildContext context, String url) {
    final uri = Uri.tryParse(url);
    return uri == null
        ? const {}
        : maybeOf(context)?.headersFor(uri) ?? const {};
  }
}
