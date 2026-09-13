import tempfile
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

from build_ios_adb import apply_source_patch, linked_archives


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
