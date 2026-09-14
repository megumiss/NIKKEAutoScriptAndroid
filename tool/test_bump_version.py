from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
POWERSHELL = shutil.which('pwsh') or shutil.which('powershell')


@unittest.skipUnless(POWERSHELL, 'Version tool tests require PowerShell')
class BumpVersionTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.script = self.root / 'tool/bump-version.ps1'
        self.script.parent.mkdir()
        shutil.copyfile(ROOT / 'tool/bump-version.ps1', self.script)
        self.pubspec = self.root / 'pubspec.yaml'
        self.about = self.root / 'lib/features/settings/about_page.dart'
        self.about.parent.mkdir(parents=True)

    def write_versions(self, version, newline='\n'):
        self.pubspec.write_bytes(f'name: fixture{newline}version: {version}{newline}'.encode('utf-8'))
        display_version = version.split('+', 1)[0]
        self.about.write_bytes(f"const appVersion = '{display_version}';{newline}".encode('utf-8'))

    def run_bump(self, *arguments):
        return subprocess.run(
            [POWERSHELL, '-NoLogo', '-NoProfile', '-NonInteractive', '-File', str(self.script), *arguments],
            capture_output=True, text=True, encoding='utf-8', timeout=30,
        )

    def test_release_parts_follow_semver_without_decimal_carry(self):
        for current, part, expected in (
            ('1.1.9', 'Patch', '1.1.10'),
            ('1.9.3', 'Minor', '1.10.0'),
            ('1.9.3', 'Major', '2.0.0'),
        ):
            with self.subTest(part=part):
                self.write_versions(current)
                result = self.run_bump('-Part', part)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.pubspec.read_text(encoding='utf-8'), f'name: fixture\nversion: {expected}\n')
                self.assertEqual(self.about.read_text(encoding='utf-8'), f"const appVersion = '{expected}';\n")

    def test_default_patch_preserves_integer_build_number_and_crlf(self):
        self.write_versions('1.1.9+42', newline='\r\n')
        result = self.run_bump()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.pubspec.read_bytes(), b'name: fixture\r\nversion: 1.1.10+42\r\n')
        self.assertEqual(self.about.read_bytes(), b"const appVersion = '1.1.10';\r\n")

    def test_dry_run_leaves_both_files_unchanged(self):
        self.write_versions('1.1.3+42')
        before = (self.pubspec.read_bytes(), self.about.read_bytes())
        result = self.run_bump('-Part', 'Minor', '-DryRun')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('1.1.3+42 -> 1.2.0+42', result.stdout)
        self.assertEqual((self.pubspec.read_bytes(), self.about.read_bytes()), before)

    def test_rejects_hash_build_number_without_writing(self):
        self.write_versions('1.1.3+6c9a43d')
        before = (self.pubspec.read_bytes(), self.about.read_bytes())
        result = self.run_bump()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.pubspec.read_bytes(), self.about.read_bytes()), before)

    def test_missing_about_version_does_not_partially_update_pubspec(self):
        self.write_versions('1.1.3')
        self.about.write_bytes(b'// No application version here.\n')
        before = (self.pubspec.read_bytes(), self.about.read_bytes())
        result = self.run_bump()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.pubspec.read_bytes(), self.about.read_bytes()), before)


if __name__ == '__main__':
    unittest.main()
