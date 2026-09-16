"""Contract tests for the Termux service scripts shipped as Android assets.

The scripts cannot run on the host (they target Termux paths and call
proot-distro), so each test builds a sandbox with stub executables on PATH and
exercises the real script logic. Asserting on behaviour rather than on source
text keeps the tests from passing when the script stops doing the right thing.

The behaviour under test is the stale-service guard: a container process left
behind by an uninstalled Termux keeps answering /api/system/status while every
filesystem-backed endpoint fails, and must not be adopted as a healthy service.
"""

import shutil
import subprocess
import tempfile
import textwrap
import time
import unittest
from pathlib import Path

ASSETS = Path(__file__).resolve().parent.parent / 'android/app/src/main/assets'
SERVICE_SCRIPT = ASSETS / 'nkas-service.sh'
BOOTSTRAP_SCRIPT = ASSETS / 'bootstrap.sh'


def _write_stub(directory: Path, name: str, body: str) -> None:
    path = directory / name
    path.write_text('#!/bin/bash\n' + textwrap.dedent(body), encoding='utf-8')
    path.chmod(0o755)


def _function_body(script: Path, name: str) -> str:
    """Return a shell function body by matching braces.

    A plain split on '}' would stop at the first ${VAR} expansion, so braces are
    counted with parameter expansions skipped.
    """
    text = script.read_text(encoding='utf-8')
    start = text.index(f'{name}()')
    depth = 0
    index = text.index('{', start)
    while index < len(text):
        char = text[index]
        if char == '$' and text[index + 1:index + 2] == '{':
            index = text.index('}', index) + 1
            continue
        if char == '{':
            depth += 1
        elif char == '}':
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
        index += 1
    raise AssertionError(f'未找到函数 {name} 的结束位置')


class ServiceScriptSandbox:
    """A Termux-like tree with stubbed proot-distro and curl."""

    def __init__(self, root: Path, *, status: str, instances: str) -> None:
        self.root = root
        self.home = root / 'home'
        self.bin = root / 'bin'
        self.state = self.home / '.nkas'
        self.state.mkdir(parents=True)
        self.bin.mkdir(parents=True)
        (self.home / 'NIKKEAutoScript').mkdir()

        # proot-distro stub: records invocations so tests can tell whether a
        # new instance was started.
        self.launches = self.state / 'proot-launches'
        _write_stub(self.bin, 'proot-distro', f"""
            echo "$@" >> "{self.launches}"
            exit 0
            """)

        # curl stub: replies per endpoint with the status configured by each
        # test, so /api/system/status and /api/instances can disagree the way a
        # stale process makes them disagree in practice.
        _write_stub(self.bin, 'curl', f"""
            url=""
            for arg in "$@"; do
                case "$arg" in
                    http*) url="$arg" ;;
                esac
            done
            case "$url" in
                */api/system/status) exit_code={status} ;;
                */api/instances) exit_code={instances} ;;
                *) exit_code=0 ;;
            esac
            if [ "$exit_code" -ne 0 ]; then
                exit 22
            fi
            echo '{{}}'
            exit 0
            """)

        _write_stub(self.bin, 'pkill', 'exit 0\n')
        _write_stub(self.bin, 'proot', 'exit 0\n')

        (self.state / 'settings.env').write_text(
            'NKAS_WEBUI_URL=http://127.0.0.1:12271\n'
            'NKAS_WEBUI_HOST=127.0.0.1\n'
            'NKAS_WEBUI_PORT=12271\n',
            encoding='utf-8',
        )
        self.script = self.state / 'nkas-service.sh'
        shutil.copy(SERVICE_SCRIPT, self.script)
        self.script.chmod(0o755)

    def run(self, *args: str) -> subprocess.CompletedProcess:
        env = {
            'HOME': str(self.home),
            'PREFIX': str(self.root / 'usr'),
            'PATH': f'{self.bin}:/usr/bin:/bin',
        }
        result = subprocess.run(
            ['bash', str(self.script), *args],
            env=env, capture_output=True, text=True,
        )
        # The script backgrounds proot-distro, so give the stub a moment to
        # record its invocation before tests inspect the launch log.
        for _ in range(50):
            if self.launches.exists() and self.launches.stat().st_size > 0:
                break
            time.sleep(0.02)
        return result

    def spawn_holder(self) -> int:
        """Start a live process in the script's PID space and return its PID.

        is_running() only checks that the recorded PID exists. The holder must
        be created by bash rather than Python: on Windows hosts Python and
        Git Bash use different PID spaces, so a Python child would be invisible
        to the kill the script performs.
        """
        result = subprocess.run(
            ['bash', '-c', 'sleep 60 >/dev/null 2>&1 & echo $!'],
            capture_output=True, text=True,
        )
        self._holder = int(result.stdout.strip())
        return self._holder

    def release_holder(self) -> None:
        subprocess.run(['bash', '-c', f'kill {self._holder}'], capture_output=True)

    def launched(self) -> bool:
        return self.launches.exists() and self.launches.stat().st_size > 0

    def write_pid(self, pid: int) -> None:
        (self.state / 'nkas.pid').write_text(f'{pid}\n', encoding='utf-8')


class StaleServiceGuardTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def sandbox(self, *, status: int, instances: int) -> ServiceScriptSandbox:
        return ServiceScriptSandbox(self.root, status=status, instances=instances)

    def test_healthy_service_is_reused_without_starting_a_second_instance(self):
        """The guard must not break the normal reuse path."""
        box = self.sandbox(status=0, instances=0)
        box.write_pid(box.spawn_holder())
        self.addCleanup(box.release_holder)

        result = box.run('start')

        self.assertEqual(result.stdout.strip(), 'running')
        self.assertFalse(box.launched(), '健康服务不应被重启')

    def test_stale_service_is_reported_instead_of_restarted(self):
        """A listener that fails the health probe must not be adopted.

        This is the reported failure: the port answers, so the old check called
        the service healthy, bootstrap reported ready, and the UI showed an
        instance-load error forever. Starting another instance would only fail
        to bind, so the script must fail loudly instead.
        """
        box = self.sandbox(status=0, instances=1)

        result = box.run('start')

        self.assertEqual(result.returncode, 1, '残留服务必须让脚本失败')
        self.assertIn('不属于当前 Termux', result.stderr)
        self.assertFalse(box.launched(), '端口被残留进程占用时不应再启动实例')

    def test_port_free_starts_a_new_instance(self):
        """With nothing listening, a start must go through."""
        box = self.sandbox(status=1, instances=1)

        result = box.run('start')

        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), 'started')
        self.assertTrue(box.launched(), '端口空闲时必须启动实例')

    def test_status_reports_stale_service_as_stopped(self):
        box = self.sandbox(status=0, instances=1)

        result = box.run('status')

        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout.strip(), 'stopped')


class ProbeTest(unittest.TestCase):
    """Both scripts must probe an endpoint that depends on the checkout."""

    def test_service_script_health_probe_reads_instances(self):
        body = _function_body(SERVICE_SCRIPT, 'is_healthy')
        self.assertIn('/api/system/status', body)
        self.assertIn('/api/instances', body)

    def test_bootstrap_readiness_probe_reads_instances(self):
        body = _function_body(BOOTSTRAP_SCRIPT, 'service_ready')
        self.assertIn('/api/system/status', body)
        self.assertIn('/api/instances', body)


if __name__ == '__main__':
    unittest.main()
