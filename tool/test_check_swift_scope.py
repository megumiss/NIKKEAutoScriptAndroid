"""Behaviour tests for the Swift cross-type scope checker.

The checker exists because a bare reference to another type's member is a
compile error that only Xcode sees: `flutter analyze` reads Dart only, and a
grep for call sites happily matches the offending line. These tests build
synthetic Swift trees and assert the checker's decision, so a regression that
silences it (or makes it cry wolf) fails here instead of surviving until the
macOS job compiles.

The cases mirror the two ways this went wrong in practice: the real
`streamTimeout` bug, and the false positives from parameter, local and closure
names that a naive scan reports.
"""

import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

CHECKER = Path(__file__).resolve().parent / 'check_swift_scope.py'


def run_checker(sources: dict[str, str]) -> subprocess.CompletedProcess:
    """Run the checker against a throwaway ios/Runner tree."""
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        runner = root / 'ios' / 'Runner'
        runner.mkdir(parents=True)
        for name, body in sources.items():
            (runner / name).write_text(textwrap.dedent(body), encoding='utf-8')
        return subprocess.run(
            [sys.executable, str(CHECKER)],
            cwd=root,
            capture_output=True,
            text=True,
        )


class CheckSwiftScopeTest(unittest.TestCase):
    def test_flags_bare_use_of_sibling_member(self):
        """The historical failure: a stream reading the client's timeout."""
        result = run_checker({
            'Client.swift': '''
                final class Client {
                  var streamTimeout: TimeInterval = 30
                  func open() { _ = Stream() }
                }

                final class Stream {
                  func write() { _ = socket.write(timeout: streamTimeout) }
                }
            ''',
        })
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('streamTimeout', result.stdout)
        # CI needs a machine-readable annotation, not just prose.
        self.assertIn('::error file=', result.stdout)

    def test_accepts_explicitly_passed_member(self):
        """The fix: the same value, handed over through the initialiser."""
        result = run_checker({
            'Client.swift': '''
                final class Client {
                  var streamTimeout: TimeInterval = 30
                  func open() { _ = Stream(writeTimeout: streamTimeout) }
                }

                final class Stream {
                  private let writeTimeout: TimeInterval
                  init(writeTimeout: TimeInterval) { self.writeTimeout = writeTimeout }
                  func write() { _ = socket.write(timeout: writeTimeout) }
                }
            ''',
        })
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_ignores_parameters_locals_and_closure_names(self):
        """A sibling declaring the same name must not make locals suspicious."""
        result = run_checker({
            'Session.swift': '''
                final class Session {
                  var endpoint: String = ""
                  func start(port: Int, handler: (Data) -> Void) {
                    let value = port
                    let length = value
                    handler(Data(endpoint.utf8))
                    _ = { count in _ = count }(length)
                  }
                }

                final class Helper {
                  func done(value: Int, length: Int, count: Int) {}
                }
            ''',
        })
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_skips_extension_members(self):
        """Extension members are not attributable, so they stay exempt."""
        result = run_checker({
            'Ext.swift': '''
                final class Box {}

                extension Box {
                  var index: Int { 0 }
                  func peek() { _ = index }
                }
            ''',
        })
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_reports_missing_tree_instead_of_passing(self):
        """Running outside the repository root must not look like success."""
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [sys.executable, str(CHECKER)],
                cwd=directory,
                capture_output=True,
                text=True,
            )
        self.assertEqual(result.returncode, 1)
        self.assertIn('ios/Runner', result.stdout)


if __name__ == '__main__':
    unittest.main()
