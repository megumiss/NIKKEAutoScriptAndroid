import 'package:flutter_test/flutter_test.dart';

import 'package:nkas_mobile/core/platform/native_control_settings.dart';

// The native side assembles this payload twice (Kotlin and Swift), so the
// parsing rules here are the only thing keeping the two in agreement. A missing
// key must degrade to the same value as an explicit null or empty one, because
// iOS previously omitted `magicDNS` entirely and the UI row silently vanished.
void main() {
  group('TsnetStatus parsing', () {
    test('reads every field from a complete payload', () {
      final status = TsnetStatus.fromMap(const {
        'phase': 'connected',
        'hostname': 'nkas-ios',
        'addresses': ['100.64.0.1', 'fd7a:115c:a1e0::1'],
        'magicDNS': 'nkas.tailnet.ts.net',
        'forwardCount': 2,
        'hasPersistedLogin': true,
        'error': '',
      });
      expect(status.phase, 'connected');
      expect(status.hostname, 'nkas-ios');
      expect(status.addresses, ['100.64.0.1', 'fd7a:115c:a1e0::1']);
      expect(status.magicDNS, 'nkas.tailnet.ts.net');
      expect(status.forwardCount, 2);
      expect(status.hasPersistedLogin, isTrue);
    });

    test('treats an absent key and an empty value alike', () {
      final absent = TsnetStatus.fromMap(const {});
      final empty = TsnetStatus.fromMap(const {
        'hostname': '',
        'addresses': <String>[],
        'magicDNS': '',
        'forwardCount': 0,
        'hasPersistedLogin': false,
        'error': '',
      });
      expect(absent.magicDNS, empty.magicDNS);
      expect(absent.addresses, empty.addresses);
      expect(absent.error, empty.error);
      expect(absent.forwardCount, empty.forwardCount);
      expect(absent.hostname, empty.hostname);
      // `phase` is the one deliberate exception: an absent phase means the node
      // has never started, which the UI distinguishes from an empty string.
      expect(absent.phase, 'new');
    });

    test('a missing magicDNS does not hide the addresses', () {
      // This is exactly the iOS payload before the fix: addresses present,
      // magicDNS absent. The IPv4/IPv6 rows must still render.
      final status = TsnetStatus.fromMap(const {
        'phase': 'connected',
        'addresses': ['100.64.0.1'],
      });
      expect(status.magicDNS, isEmpty);
      expect(status.addresses, ['100.64.0.1']);
    });

    test('splits addresses into IPv4 and IPv6 without dropping either', () {
      final status = TsnetStatus.fromMap(const {
        'addresses': ['fd7a:115c:a1e0::1', '100.64.0.1'],
      });
      final ipv4 = status.addresses.firstWhere((a) => a.contains('.'));
      final ipv6 = status.addresses.firstWhere((a) => a.contains(':'));
      expect(ipv4, '100.64.0.1');
      expect(ipv6, 'fd7a:115c:a1e0::1');
    });

    test('tolerates a non-integer forwardCount', () {
      final status = TsnetStatus.fromMap(const {'forwardCount': 1.0});
      expect(status.forwardCount, 1);
    });
  });
}
