"""Pin the Tailscale status contract across the Dart, Kotlin and Swift layers.

The status payload is assembled three times -- once in Go, then reshaped by each
platform bridge -- and Dart reads it with silent defaults. That combination let
iOS ship without ever forwarding `magicDNS`: Android mapped it, iOS did not, and
because `TsnetStatus.fromMap` falls back to '' for a missing key, the MagicDNS
row simply never appeared on iOS instead of failing anywhere.

These tests read the native sources directly. They are not a substitute for
running on a device; they exist because a key that is present on one platform
and absent on the other is invisible to every Dart and XCTest assertion.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GO_BRIDGE = ROOT / 'native/tsnet/bridge.go'
KOTLIN = ROOT / 'android/app/src/main/kotlin/com/megumiss/nkas/mobile/platform/NativeTsnet.kt'
SWIFT = ROOT / 'ios/Runner/NkasTsnet.swift'
DART = ROOT / 'lib/core/platform/native_control_settings.dart'

# Keys the UI depends on: phase drives the state row, addresses and magicDNS
# feed the network-detail rows, error is rendered when a connection fails.
REQUIRED_KEYS = ['phase', 'hostname', 'addresses', 'magicDNS', 'forwardCount', 'error']


def read(path: Path) -> str:
    return path.read_text(encoding='utf-8')


class TailscaleStatusContractTest(unittest.TestCase):
    def test_go_bridge_marshals_every_key(self):
        body = read(GO_BRIDGE)
        start = body.index('func (c *Client) Status()')
        block = body[start:body.index('\n}', start)]
        for key in REQUIRED_KEYS:
            self.assertIn(f'"{key}"', block, f'Go Status() 缺少 {key}')

    def test_kotlin_forwards_every_key(self):
        body = read(KOTLIN)
        start = body.index('fun status()')
        block = body[start:body.index('\n    }', start)]
        for key in REQUIRED_KEYS:
            self.assertIn(f'"{key}"', block, f'Android status() 缺少 {key}')

    def test_swift_forwards_every_key(self):
        """The regression: iOS must not rely on Dart's '' default for magicDNS.

        Unlike Android, `phase`, `error` and `forwardCount` are not re-marshalled
        here -- they pass through from Go inside `value`. So the fields iOS must
        actively normalise are the ones Dart would otherwise read as missing.
        """
        body = read(SWIFT)
        start = body.index('func status() -> [String: Any]')
        block = body[start:body.index('\n  }', start)]
        for key in ['addresses', 'magicDNS']:
            self.assertIn(
                f'"{key}"', block,
                f'iOS status() 没有为 {key} 兜底；Dart 侧会静默取默认值',
            )
        # The pass-through fields must still survive: asserted on the Go source
        # in test_go_bridge_marshals_every_key, and Dart reads them.
        self.assertIn('client.status()', block)

    def test_all_platforms_agree_on_normalisation(self):
        """An absent key and an empty one must land the same way in Dart."""
        dart = read(DART)
        for key in ['addresses', 'magicDNS', 'forwardCount', 'error', 'phase']:
            self.assertIn(key, dart, f'TsnetStatus 未解析 {key}')
        # Both natives must replace null with a usable value rather than drop it.
        self.assertRegex(read(SWIFT), r'value\["magicDNS"\]\s+is\s+NSNull')
        self.assertRegex(read(KOTLIN), r'"magicDNS"\s+to\s+value\.optString')

    def test_ui_renders_magicdns_only_when_present(self):
        """The row is conditional, which is why the gap was silent.

        It reads from the last connected snapshot rather than the live status,
        because the forwarder teardown that follows every connection clears
        `addresses` and `magicDNS` before the UI can render them.
        """
        page = read(ROOT / 'lib/features/settings/native_control_page.dart')
        self.assertIn("('MagicDNS', source.magicDNS)", page)
        self.assertIn('source.magicDNS.isNotEmpty', page)
        # Rendering must not be gated on the live phase, or nothing shows after
        # the connection is closed.
        self.assertNotIn("if (status.phase == 'connected')\n                        ..._networkDetails", page)


if __name__ == '__main__':
    unittest.main()
