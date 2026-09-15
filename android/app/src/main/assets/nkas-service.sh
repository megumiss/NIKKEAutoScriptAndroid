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

is_healthy() {
    command -v curl >/dev/null 2>&1 || return 1
    curl -fsS --max-time 3 "${WEBUI_URL}/api/system/status" >/dev/null 2>&1
}

kill_service() {
    if is_running; then
        kill "$(cat "$PID_FILE")" 2>/dev/null || true
    fi
    # proot-distro 不转发信号，启动器退出后内层 python 可能继续占用端口
    pkill -f 'gui[.]py' 2>/dev/null || true
    rm -f "$PID_FILE"
}

start_service() {
    if is_running && is_healthy; then
        echo "running"
        return 0
    fi
    kill_service
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
