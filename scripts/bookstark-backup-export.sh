#!/usr/bin/env bash
set -euo pipefail

# This script runs on the production server through a forced SSH command. It
# writes only the backup archive to stdout; diagnostics belong on stderr.
if [ "${SSH_ORIGINAL_COMMAND:-}" = "probe" ]; then
    echo "bookstark-backup-export-ready"
    exit 0
fi
if [ -n "${SSH_ORIGINAL_COMMAND:-}" ]; then
    echo "Unsupported backup command." >&2
    exit 64
fi

DATA_DIR="${BOOKSTARK_DATA_DIR:-/root/docker/bookstark}"
COMPOSE_FILE="${BOOKSTARK_COMPOSE_FILE:-/root/docker/bookstark.yml}"
WORK_DIR="$(mktemp -d /tmp/bookstark-backup-export.XXXXXX)"
trap 'rm -rf -- "${WORK_DIR}"' EXIT
umask 077

python3 - "${DATA_DIR}" "${WORK_DIR}" <<'PY'
import pathlib
import sqlite3
import sys

data_dir = pathlib.Path(sys.argv[1])
work_dir = pathlib.Path(sys.argv[2])
for name in ("bookstark.db", "bookstark-webdav.db", "share_comments.db"):
    source_path = data_dir / name
    if not source_path.is_file():
        raise SystemExit(f"required database is missing: {source_path}")
    destination_path = work_dir / name
    source = sqlite3.connect(f"file:{source_path}?mode=ro", uri=True, timeout=30)
    destination = sqlite3.connect(destination_path)
    try:
        source.execute("PRAGMA busy_timeout=30000")
        source.backup(destination, pages=2048, sleep=0.05)
        result = destination.execute("PRAGMA quick_check").fetchone()
        if result is None or result[0] != "ok":
            raise RuntimeError(f"quick_check failed for {name}: {result}")
    finally:
        destination.close()
        source.close()
PY

if [ -d "${DATA_DIR}/uploads" ]; then
    tar -C "${DATA_DIR}" -czf "${WORK_DIR}/uploads.tar.gz" uploads
else
    mkdir -p "${WORK_DIR}/empty/uploads"
    tar -C "${WORK_DIR}/empty" -czf "${WORK_DIR}/uploads.tar.gz" uploads
fi

install -m 600 "${COMPOSE_FILE}" "${WORK_DIR}/bookstark-compose.yml"
IMAGE="$(docker inspect bookstark --format '{{.Config.Image}}' 2>/dev/null || true)"
REVISION="$(docker inspect bookstark --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' 2>/dev/null || true)"
if [ -z "${IMAGE}" ] || [ -z "${REVISION}" ]; then
    echo "Unable to identify the running BookStark image and revision." >&2
    exit 1
fi
docker image save "${IMAGE}" | gzip -1 > "${WORK_DIR}/bookstark-image.tar.gz"
gzip -t "${WORK_DIR}/bookstark-image.tar.gz"
{
    echo "generated_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "source_host=$(hostname)"
    echo "image=${IMAGE}"
    echo "revision=${REVISION}"
    echo "sqlite_method=online_backup_api"
} > "${WORK_DIR}/manifest.txt"

tar -C "${WORK_DIR}" -cf - \
    bookstark.db \
    bookstark-webdav.db \
    share_comments.db \
    uploads.tar.gz \
    bookstark-image.tar.gz \
    bookstark-compose.yml \
    manifest.txt | gzip -1
