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
    test('per-instance override wins over global and backend serial', () {
      const settings = NativeControlSettings(
        endpoint: 'global:5555',
        endpoints: {'nkas': 'override:5555'},
      );
      expect(
        settings.endpointFor('nkas', backendSerial: 'backend:5555'),
        'override:5555',
      );
    });

    test('global manual endpoint beats backend serial', () {
      const settings = NativeControlSettings(endpoint: 'global:5555');
      expect(
        settings.endpointFor('nkas', backendSerial: 'backend:5555'),
        'global:5555',
      );
    });

    test('backend serial is the default when nothing is overridden', () {
      const settings = NativeControlSettings();
      expect(
        settings.endpointFor('nkas', backendSerial: 'backend:5555'),
        'backend:5555',
      );
      expect(settings.endpointFor('nkas'), isEmpty);
    });

    test('blank override falls through to global endpoint', () {
      const settings = NativeControlSettings(
        endpoint: 'global:5555',
        endpoints: {'nkas': '  '},
      );
      expect(settings.endpointFor('nkas'), 'global:5555');
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
