#!/usr/bin/env bash
set -euo pipefail

REMOTE_HOST="${BOOKSTARK_BACKUP_HOST:-www.vs2010wy.top}"
REMOTE_PORT="${BOOKSTARK_BACKUP_PORT:-28246}"
REMOTE_USER="${BOOKSTARK_BACKUP_USER:-root}"
SSH_KEY="${BOOKSTARK_BACKUP_KEY:-/root/.ssh/bookstark_production_backup_ed25519}"
DEST_DIR="${BOOKSTARK_BACKUP_DEST:-/vol1/1000/wy/backups/bookstark}"
BACKUP_OWNER="${BOOKSTARK_BACKUP_OWNER:-wy:Users}"
LOCK_FILE="${BOOKSTARK_BACKUP_LOCK:-/run/lock/bookstark-production-backup.lock}"
REQUIRED=(bookstark.db bookstark-webdav.db share_comments.db uploads.tar.gz bookstark-compose.yml manifest.txt)

umask 077
exec 9>"${LOCK_FILE}"
flock -n 9 || { echo "BookStark production backup is already running." >&2; exit 0; }

install -d -m 700 -o "${BACKUP_OWNER%:*}" -g "${BACKUP_OWNER#*:}" "${DEST_DIR}"
STAGE_DIR="$(mktemp -d "${DEST_DIR}/.incoming.XXXXXX")"
trap 'rm -rf -- "${STAGE_DIR}"' EXIT
ARCHIVE="${STAGE_DIR}/backup.tar.gz"
PAYLOAD="${STAGE_DIR}/payload"
mkdir -m 700 "${PAYLOAD}"

ssh \
    -T \
    -i "${SSH_KEY}" \
    -p "${REMOTE_PORT}" \
    -o BatchMode=yes \
    -o ConnectTimeout=20 \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=4 \
    -o StrictHostKeyChecking=yes \
    "${REMOTE_USER}@${REMOTE_HOST}" > "${ARCHIVE}"

gzip -t "${ARCHIVE}"
mapfile -t MEMBERS < <(tar -tzf "${ARCHIVE}" | sort)
mapfile -t EXPECTED < <(printf '%s\n' "${REQUIRED[@]}" | sort)
if [ "${MEMBERS[*]}" != "${EXPECTED[*]}" ]; then
    printf 'Unexpected backup archive members:\n%s\n' "${MEMBERS[*]}" >&2
    exit 1
fi
tar -xzf "${ARCHIVE}" -C "${PAYLOAD}"

python3 - "${PAYLOAD}" <<'PY'
import pathlib
import sqlite3
import sys

payload = pathlib.Path(sys.argv[1])
for name in ("bookstark.db", "bookstark-webdav.db", "share_comments.db"):
    path = payload / name
    connection = sqlite3.connect(f"file:{path}?mode=ro&immutable=1", uri=True, timeout=30)
    try:
        result = connection.execute("PRAGMA quick_check").fetchone()
        if result is None or result[0] != "ok":
            raise SystemExit(f"quick_check failed for {name}: {result}")
    finally:
        connection.close()
PY
tar -tzf "${PAYLOAD}/uploads.tar.gz" >/dev/null

# All payloads are now complete and verified. Replace the fixed names, with the
# manifest moved last so its timestamp marks a fully published backup set.
for name in bookstark.db bookstark-webdav.db share_comments.db uploads.tar.gz bookstark-compose.yml; do
    chmod 600 "${PAYLOAD}/${name}"
    chown "${BACKUP_OWNER}" "${PAYLOAD}/${name}"
    mv -f -- "${PAYLOAD}/${name}" "${DEST_DIR}/${name}"
done
chmod 600 "${PAYLOAD}/manifest.txt"
chown "${BACKUP_OWNER}" "${PAYLOAD}/manifest.txt"
mv -f -- "${PAYLOAD}/manifest.txt" "${DEST_DIR}/manifest.txt"

echo "BookStark production backup updated: ${DEST_DIR}"

