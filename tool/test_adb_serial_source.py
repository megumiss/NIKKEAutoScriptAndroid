"""Pin the ADB serial to a single source of truth.

adbd reassigns its wireless-debug port on every boot, so any serial captured
into a file goes stale the next time the phone restarts. The app ended up with
two stores that disagreed:

* ``SettingsStore`` (SharedPreferences) -- what the UI reads, refreshed at
  runtime whenever mDNS discovers the current ``_adb-tls-connect._tcp`` port.
* ``$HOME/.nkas/settings.env`` -- written once by ``startBootstrap`` and never
  updated, so it keeps the port that was current when the bootstrap last ran.

``checkArtifacts`` used to source ``settings.env`` and use its ``NKAS_SERIAL``,
so the page could show the live port while ``adb connect`` dialled the dead one
and logged ``Connection refused``. These tests read the Kotlin source, because
the two stores drift silently -- nothing fails at compile time, and the UI stays
internally consistent while the probe uses the wrong value.
"""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / 'android/app/src/main/kotlin/com/megumiss/nkas/mobile/platform/TermuxBridge.kt'
SETTINGS_STORE = ROOT / 'android/app/src/main/kotlin/com/megumiss/nkas/mobile/platform/SettingsStore.kt'


def read(path: Path) -> str:
    return path.read_text(encoding='utf-8')


def function_body(source: str, signature: str, terminator: str = '\n    }') -> str:
    start = source.index(signature)
    return source[start:source.index(terminator, start)]


class AdbSerialSourceTest(unittest.TestCase):
    def test_probe_serial_comes_from_settings_store(self):
        """The probe must dial the same serial the UI shows."""
        body = function_body(read(BRIDGE), 'fun checkArtifacts(')
        self.assertIn(
            'SettingsStore.serial(context)',
            body,
            'checkArtifacts 必须从 SettingsStore 取 serial，否则界面显示的值与探测用的值会不一致',
        )

    def test_probe_serial_is_not_read_from_the_env_file(self):
        """Sourcing settings.env is still needed for the WebUI URL, so the test
        pins the serial specifically: the script must not resolve it from
        NKAS_SERIAL, which only the bootstrap ever writes."""
        body = function_body(read(BRIDGE), 'fun checkArtifacts(')
        self.assertNotIn(
            'configured_serial="${NKAS_SERIAL',
            body,
            '探测脚本不得从 settings.env 的 NKAS_SERIAL 取 serial：该值只在 bootstrap 时写入，重启后即过期',
        )

    def test_env_file_does_not_shadow_the_injected_serial(self):
        """`source settings.env` assigns NKAS_SERIAL, so an injected value must
        be assigned after it -- otherwise the stale file wins again."""
        body = function_body(read(BRIDGE), 'fun checkArtifacts(')
        source_at = body.index('termux_home/.nkas/settings.env')
        assign_at = body.index('configured_serial=')
        self.assertGreater(
            assign_at,
            source_at,
            'configured_serial 必须在 source settings.env 之后赋值，否则会被文件里的旧值覆盖',
        )

    def test_settings_store_is_the_only_runtime_store(self):
        """Guards the premise: if a second store is introduced, this file needs
        to grow a matching assertion rather than silently keeping its old one."""
        body = read(SETTINGS_STORE)
        self.assertIn('"serial"', body)
        self.assertIn('PREFS_NAME', body)


if __name__ == '__main__':
    unittest.main()
