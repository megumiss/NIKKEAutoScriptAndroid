#!/data/data/com.termux/files/usr/bin/bash
set -u

REPO_DIR="${HOME}/NIKKEAutoScript"
STATE_DIR="${HOME}/.nkas"
PID_FILE="${STATE_DIR}/nkas.pid"
LOG_FILE="${STATE_DIR}/nkas-service.log"
mkdir -p "$STATE_DIR"
if [ -f "$STATE_DIR/settings.env" ]; then
    . "$STATE_DIR/settings.env"
fi
WEBUI_URL="${NKAS_WEBUI_URL:-http://127.0.0.1:12271}"
WEBUI_HOST="${NKAS_WEBUI_HOST:-127.0.0.1}"
WEBUI_PORT="${NKAS_WEBUI_PORT:-12271}"

is_running() {
    [ -f "$PID_FILE" ] || return 1
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# Health probe: /api/system/status only reads in-memory state, so a stale
# process whose working directory no longer resolves still answers 200 while
# every filesystem-backed endpoint fails. /api/instances reads ./config, which
# is resolved against the process working directory, so it fails exactly when
# the service is no longer bound to the current checkout. Probing it keeps a
# leftover container process from being mistaken for a healthy service.
is_healthy() {
    command -v curl >/dev/null 2>&1 || return 1
    curl -fsS --max-time 3 "${WEBUI_URL}/api/system/status" >/dev/null 2>&1 || return 1
    curl -fsS --max-time 5 "${WEBUI_URL}/api/instances" >/dev/null 2>&1
}

# A leftover container process keeps listening on WEBUI_PORT after its Termux
# was uninstalled and reinstalled: uninstalling kills the Termux process tree
# outright, so the proot launcher never runs its --kill-on-exit cleanup and the
# guest python is reparented to init, still holding the port. The reinstalled
# Termux runs under a NEW Android uid, and Android separates /proc per uid, so
# the old guest is invisible to pkill here (/proc/net/tcp is not even readable).
# Only the port is observable, hence this probe; pair it with ! is_healthy to
# tell a stale listener apart from a working service.
port_in_use() {
    command -v curl >/dev/null 2>&1 || return 1
    curl -fsS --max-time 3 "${WEBUI_URL}/api/system/status" >/dev/null 2>&1
}

kill_service() {
    if is_running; then
        kill "$(cat "$PID_FILE")" 2>/dev/null || true
    fi
    # proot-distro 不转发信号，启动器退出后内层 python 可能继续占用端口。
    # 这只对同一个 Termux 进程树内有效；跨 uid 的残留进程杀不到，见下方提示。
    pkill -f 'gui[.]py' 2>/dev/null || true
    rm -f "$PID_FILE"
}

# A stale service can only be removed from inside its own container, which the
# user cannot enter once the owning Termux is gone. Report it instead of
# starting a second instance that would fail to bind and exit silently.
stale_service_error() {
    printf 'NKAS WebUI 端口 %s 上的服务无法使用，且该进程不属于当前 Termux。\n' "$WEBUI_PORT" >&2
    printf '这通常是卸载重装 Termux 后旧容器进程未随之退出导致的：\n' >&2
    printf '该进程的工作目录指向已被删除的旧仓库，所有依赖配置的接口都会失败。\n' >&2
    printf '它无法被当前 Termux 终止，请重启手机后重试安装。\n' >&2
}

start_service() {
    if is_running && is_healthy; then
        echo "running"
        return 0
    fi
    kill_service
    # Something still answers on the port but failed the health probe above:
    # a process from a previous Termux survived and cannot be signalled from
    # here. Starting a new instance would only fail to bind and exit silently,
    # so surface the cause instead.
    if port_in_use && ! is_healthy; then
        stale_service_error
        return 1
    fi
    [ -d "$REPO_DIR" ] || { echo "NKAS repository is missing" >&2; return 1; }
    nohup proot-distro run \
        -b "$REPO_DIR:/app/NIKKEAutoScript" \
        -w /app/NIKKEAutoScript \
        nkas -- /usr/local/bin/python gui.py --host "$WEBUI_HOST" --port "$WEBUI_PORT" \
        >>"$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    echo "started"
}

stop_service() {
    kill_service
    echo "stopped"
}

status_service() {
    if is_running && is_healthy; then
        echo "running"
        return 0
    fi
    echo "stopped"
    return 1
}

case "${1:-status}" in
    start) start_service ;;
    stop) stop_service ;;
    restart) stop_service; start_service ;;
    status) status_service ;;
    *) echo "usage: $0 {start|stop|restart|status}" >&2; exit 2 ;;
esac
