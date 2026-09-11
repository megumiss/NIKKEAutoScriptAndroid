import 'dart:typed_data';

class ScreenshotFrame {
  const ScreenshotFrame({required this.bytes, this.capturedAt});

  final Uint8List bytes;
  final double? capturedAt;
}
