import 'package:flutter_test/flutter_test.dart';
import 'package:nkas_mobile/core/platform/native_control_settings.dart';

void main() {
  group('backendSerialOf', () {
    test('reads Emulator.Emulator.Serial from an instance config', () {
      expect(
        backendSerialOf({
          'Emulator': {
            'Emulator': {'Serial': '127.0.0.1:5555', 'PackageName': 'x'},
          },
        }),
        '127.0.0.1:5555',
      );
    });

    test('auto, empty and missing values are not connectable', () {
      expect(
        backendSerialOf({
          'Emulator': {
            'Emulator': {'Serial': 'auto'},
          },
        }),
        isNull,
      );
      expect(
        backendSerialOf({
          'Emulator': {
            'Emulator': {'Serial': ''},
          },
        }),
        isNull,
      );
      expect(backendSerialOf({'Emulator': {}}), isNull);
      expect(backendSerialOf({}), isNull);
    });
  });

  group('endpointFor', () {
    test('per-instance override wins over backend serial', () {
      const settings = NativeControlSettings(
        endpoint: 'global:5555',
        endpoints: {'nkas': 'override:5555'},
      );
      expect(
        settings.endpointFor('nkas', backendSerial: 'backend:5555'),
        'override:5555',
      );
    });

    test('backend serial beats the stored manual endpoint', () {
      const settings = NativeControlSettings(endpoint: 'global:5555');
      expect(
        settings.endpointFor('nkas', backendSerial: 'backend:5555'),
        'backend:5555',
      );
      // 手填的固定地址不参与实例解析，仅由调用方在无实例列表时兜底
      expect(settings.endpointFor('nkas'), isEmpty);
    });

    test('backend serial is the default when nothing is overridden', () {
      const settings = NativeControlSettings();
      expect(
        settings.endpointFor('nkas', backendSerial: 'backend:5555'),
        'backend:5555',
      );
      expect(settings.endpointFor('nkas'), isEmpty);
    });

    test('blank override falls through to backend serial', () {
      const settings = NativeControlSettings(
        endpoint: 'global:5555',
        endpoints: {'nkas': '  '},
      );
      expect(
        settings.endpointFor('nkas', backendSerial: 'backend:5555'),
        'backend:5555',
      );
      expect(settings.endpointFor('nkas'), isEmpty);
    });
  });

  test('settings map roundtrip keeps endpoints', () {
    const settings = NativeControlSettings(
      endpoint: 'global:5555',
      endpoints: {'nkas': 'override:5555'},
    );
    final restored = NativeControlSettings.fromMap(settings.toMap());
    expect(restored.endpoint, 'global:5555');
    expect(restored.endpoints, {'nkas': 'override:5555'});
  });
}
