from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import verify_native
from build_tsnet import ANDROID_ABIS


class ApkVerificationTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.apk = Path(temporary.name) / 'app.apk'

    def write_apk(self, abis, *, missing=None, empty=None, stale_license=False):
        with zipfile.ZipFile(self.apk, 'w') as archive:
            archive.write(verify_native.ROOT / 'ios/Runner/scrcpy-server-v4.1',
                          'assets/bin/scrcpy-server-v4.1')
            for abi in abis:
                for library in ('libgojni.so', 'libflutter.so', 'libapp.so'):
                    name = f'lib/{abi}/{library}'
                    if name != missing:
                        archive.writestr(name, b'' if name == empty else b'native fixture')
            for group in ('go', 'ios', 'shared'):
                data = (verify_native.ROOT / f'assets/licenses/{group}.json').read_bytes()
                archive.writestr(f'assets/flutter_assets/assets/licenses/{group}.json',
                                 b'[]' if stale_license and group == 'go' else data)

    def verify(self, abi=None):
        with patch('builtins.print'):
            verify_native.verify_apk(self.apk, abi)

    def test_accepts_universal_and_each_split_apk(self):
        for abi in (None, *sorted(ANDROID_ABIS)):
            with self.subTest(abi=abi):
                self.write_apk({abi} if abi else ANDROID_ABIS)
                self.verify(abi)

    def test_rejects_split_apk_when_universal_is_expected(self):
        self.write_apk({'arm64-v8a'})
        with self.assertRaisesRegex(SystemExit, 'Unexpected APK ABIs'):
            self.verify()

    def test_rejects_wrong_or_extra_split_architectures(self):
        for abis in ({'armeabi-v7a'}, ANDROID_ABIS):
            with self.subTest(abis=abis):
                self.write_apk(abis)
                with self.assertRaisesRegex(SystemExit, 'Unexpected APK ABIs'):
                    self.verify('arm64-v8a')

    def test_rejects_incomplete_native_runtime(self):
        for library in ('libgojni.so', 'libflutter.so'):
            with self.subTest(library=library):
                self.write_apk(ANDROID_ABIS, missing=f'lib/x86_64/{library}')
                with self.assertRaisesRegex(SystemExit, 'ABIs incomplete'):
                    self.verify()

    def test_rejects_empty_native_library(self):
        self.write_apk({'arm64-v8a'}, empty='lib/arm64-v8a/libgojni.so')
        with self.assertRaisesRegex(SystemExit, 'Empty APK native library'):
            self.verify('arm64-v8a')

    def test_split_apk_still_requires_current_licenses(self):
        self.write_apk({'arm64-v8a'}, stale_license=True)
        with self.assertRaisesRegex(SystemExit, 'missing current native licenses'):
            self.verify('arm64-v8a')


if __name__ == '__main__':
    unittest.main()
