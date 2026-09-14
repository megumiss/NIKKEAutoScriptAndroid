import tempfile
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

import collect_native_licenses
from build_ios_adb import apply_source_patch, linked_archives
from collect_native_licenses import license_files


class NativeLicenseInputsTest(unittest.TestCase):
    def test_license_order_is_independent_of_host_path_case_rules(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            nested = root / 'internal/sync/singleflight'
            nested.mkdir(parents=True)
            for path in (root / 'LICENSE', root / 'NOTICE', nested / 'LICENSE'):
                path.touch()
            paths = [path.relative_to(root).as_posix() for path in license_files(root, {nested})]
            self.assertEqual(paths, ['LICENSE', 'NOTICE', 'internal/sync/singleflight/LICENSE'])

    def test_aosp_license_is_independent_of_the_application_license(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            root.joinpath('LICENSE').write_text('GNU General Public License version 3', encoding='utf-8')
            apache = root / 'LICENSES/Apache-2.0.txt'
            apache.parent.mkdir()
            apache.write_text('Apache License, Version 2.0', encoding='utf-8')
            adb = root / 'cache/adb-mobile'
            for relative in ('libziparchive/zip_archive.cc', 'core/libcrypto_utils/android_pubkey.cpp',
                             'core/diagnose_usb/diagnose_usb.cpp'):
                source = adb / 'android-tools/vendor' / relative
                source.parent.mkdir(parents=True, exist_ok=True)
                source.write_text('/* AOSP copyright header */\n', encoding='utf-8')
            revisions = {
                adb: collect_native_licenses.ADB_REVISION,
                adb / 'external/protobuf': collect_native_licenses.PROTOBUF_REVISION,
            }
            with patch('collect_native_licenses.ROOT', root), \
                    patch('collect_native_licenses.CACHE', root / 'cache'), \
                    patch('collect_native_licenses.capture',
                          side_effect=lambda *args, cwd: revisions.get(cwd, 'fixture')), \
                    patch('collect_native_licenses.entry', return_value={}):
                entries = collect_native_licenses.collect_ios()
            aosp = [entry for entry in entries if entry.get('name', '').startswith('AOSP ')]
            self.assertEqual(len(aosp), 3)
            for entry in aosp:
                with self.subTest(component=entry['name']):
                    self.assertEqual(entry['licenses'][1]['text'], 'Apache License, Version 2.0')


class NativeLinkInputsTest(unittest.TestCase):
    def test_applies_windows_mail_patch_with_bare_empty_context_line(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repository = root / 'source'
            repository.mkdir()
            subprocess.run(['git', 'init', '--quiet', str(repository)], check=True)
            source = repository / 'file.cpp'
            source.write_text('before\n\nkeep\n', encoding='utf-8')
            diff = root / 'change.patch'
            diff.write_bytes(b'--- a/file.cpp\r\n+++ b/file.cpp\r\n@@ -1,3 +1,3 @@\r\n'
                             b'-before\r\n+after\r\n\r\n keep\r\n')
            with patch('build_ios_adb.CACHE', root / 'cache'):
                apply_source_patch(repository, diff)
            self.assertEqual(source.read_text(encoding='utf-8'), 'after\n\nkeep\n')

    def test_reads_cmake_relative_archives_with_spaces_and_deduplicates(self):
        with tempfile.TemporaryDirectory() as temporary:
            build = Path(temporary) / 'build with spaces'
            command = build / 'vendor/CMakeFiles/nkas_adb_link_check.dir/link.txt'
            command.parent.mkdir(parents=True)
            adb = build / 'vendor/liblibadb.a'
            protobuf = build / 'protobuf/libprotobuf.a'
            protobuf.parent.mkdir()
            adb.touch()
            protobuf.touch()
            command.write_text('clang++ obj.o -o nkas_adb_link_check liblibadb.a '
                               '../protobuf/libprotobuf.a liblibadb.a -lz', encoding='utf-8')
            directory, _, archives = linked_archives(build)
            self.assertEqual(directory, build / 'vendor')
            self.assertEqual(archives, [adb.resolve(), protobuf.resolve()])

    def test_rejects_a_host_library_outside_the_ios_build(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build = root / 'ios'
            command = build / 'vendor/CMakeFiles/nkas_adb_link_check.dir/link.txt'
            command.parent.mkdir(parents=True)
            (root / 'host.a').touch()
            command.write_text('clang++ obj.o -o check ../../host.a', encoding='utf-8')
            with self.assertRaisesRegex(SystemExit, 'Unexpected static archive'):
                linked_archives(build)


if __name__ == '__main__':
    unittest.main()
