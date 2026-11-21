#!/usr/bin/env bash
set -euo pipefail

CODEX_BIN="/root/.codex/packages/standalone/current/bin/codex"
PROXY_URL="http://127.0.0.1:58080"
CODEX_REMOTE_CONFIG=(
    -c 'sandbox_mode="danger-full-access"'
    -c 'approval_policy="never"'
)

export http_proxy="${PROXY_URL}"
export https_proxy="${PROXY_URL}"
export HTTP_PROXY="${PROXY_URL}"
export HTTPS_PROXY="${PROXY_URL}"
export all_proxy="${PROXY_URL}"
export ALL_PROXY="${PROXY_URL}"
export NO_PROXY=localhost,127.0.0.1,::1
export no_proxy=localhost,127.0.0.1,::1

"${CODEX_BIN}" remote-control stop || true

# `remote-control stop` can leave the pid-update-loop around briefly. Kill any
# stale app-server daemon pieces so the next start inherits the proxy env.
pkill -f '/root/.codex/packages/standalone/current/codex app-server' 2>/dev/null || true
sleep 1

"${CODEX_BIN}" remote-control start "${CODEX_REMOTE_CONFIG[@]}"

APP_PID="$(sed -n 's/.*"pid":\([0-9][0-9]*\).*/\1/p' /root/.codex/app-server-daemon/app-server.pid 2>/dev/null || true)"
UPDATER_PID="$(sed -n 's/.*"pid":\([0-9][0-9]*\).*/\1/p' /root/.codex/app-server-daemon/app-server-updater.pid 2>/dev/null || true)"

for pid in "${APP_PID}" "${UPDATER_PID}"; do
    if [ -n "${pid}" ] && [ -r "/proc/${pid}/environ" ]; then
        echo
        echo "proxy env for pid ${pid}:"
        tr '\0' '\n' < "/proc/${pid}/environ" | grep -i proxy || true
    fi
done



