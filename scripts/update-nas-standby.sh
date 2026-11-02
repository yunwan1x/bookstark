#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BOOKSTARK_BACKUP_DEST:-/vol1/1000/wy/backups/bookstark}"
STANDBY_ROOT="${BOOKSTARK_STANDBY_ROOT:-/vol1/1000/wy/services/bookstark-standby}"
STANDBY_OWNER="${BOOKSTARK_STANDBY_OWNER:-wy:Users}"
CONTAINER_NAME="${BOOKSTARK_STANDBY_CONTAINER:-bookstark-standby}"
BIND_ADDRESS="${BOOKSTARK_STANDBY_BIND:-0.0.0.0}"
PUBLISHED_PORT="${BOOKSTARK_STANDBY_PORT:-8089}"
PROJECT_NAME="${BOOKSTARK_STANDBY_PROJECT:-bookstark-standby}"
HEALTH_URL="${BOOKSTARK_STANDBY_HEALTH_URL:-http://127.0.0.1:${PUBLISHED_PORT}/}"
CURRENT_DIR="${STANDBY_ROOT}/current"
REQUIRED=(bookstark.db bookstark-webdav.db share_comments.db uploads.tar.gz bookstark-image.tar.gz bookstark-compose.yml manifest.txt)

umask 077

for name in "${REQUIRED[@]}"; do
    if [ ! -f "${BACKUP_DIR}/${name}" ]; then
        echo "Missing verified backup file: ${BACKUP_DIR}/${name}" >&2
        exit 1
    fi
done

IMAGE="$(sed -n 's/^image=//p' "${BACKUP_DIR}/manifest.txt")"
REVISION="$(sed -n 's/^revision=//p' "${BACKUP_DIR}/manifest.txt")"
if ! [[ "${IMAGE}" =~ ^[A-Za-z0-9][A-Za-z0-9._/@:-]*$ ]]; then
    echo "Invalid image reference in manifest: ${IMAGE}" >&2
    exit 1
fi
if ! [[ "${REVISION}" =~ ^[0-9a-f]{40}$ ]]; then
    echo "Invalid image revision in manifest: ${REVISION}" >&2
    exit 1
fi
if ! [[ "${PUBLISHED_PORT}" =~ ^[0-9]+$ ]] || [ "${PUBLISHED_PORT}" -lt 1 ] || [ "${PUBLISHED_PORT}" -gt 65535 ]; then
    echo "Invalid standby port: ${PUBLISHED_PORT}" >&2
    exit 1
fi

# Load the production image archive and verify it before interrupting the
# currently running standby. This does not depend on the registry retaining an
# immutable deployment tag.
gzip -dc "${BACKUP_DIR}/bookstark-image.tar.gz" | docker image load
IMAGE_REVISION="$(docker image inspect "${IMAGE}" --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}')"
if [ "${IMAGE_REVISION}" != "${REVISION}" ]; then
    echo "Standby image revision mismatch: expected ${REVISION}, got ${IMAGE_REVISION}" >&2
    exit 1
fi

install -d -m 700 -o "${STANDBY_OWNER%:*}" -g "${STANDBY_OWNER#*:}" "${STANDBY_ROOT}"
NEXT_DIR="$(mktemp -d "${STANDBY_ROOT}/.next.XXXXXX")"
OLD_DIR=""
cleanup() {
    if [ -n "${NEXT_DIR:-}" ] && [ -d "${NEXT_DIR}" ]; then
        rm -rf -- "${NEXT_DIR}"
    fi
}
trap cleanup EXIT
mkdir -m 700 "${NEXT_DIR}/data"

for name in bookstark.db bookstark-webdav.db share_comments.db; do
    install -m 600 "${BACKUP_DIR}/${name}" "${NEXT_DIR}/data/${name}"
done

# Only regular files and directories rooted below uploads/ may be restored.
python3 - "${BACKUP_DIR}/uploads.tar.gz" <<'PY'
import pathlib
import sys
import tarfile

archive_path = pathlib.Path(sys.argv[1])
with tarfile.open(archive_path, "r:gz") as archive:
    members = archive.getmembers()
    if not members:
        raise SystemExit("uploads archive is empty")
    for member in members:
        path = pathlib.PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts or not path.parts or path.parts[0] != "uploads":
            raise SystemExit(f"unsafe uploads archive path: {member.name}")
        if not (member.isfile() or member.isdir()):
            raise SystemExit(f"unsupported uploads archive member: {member.name}")
PY
tar -xzf "${BACKUP_DIR}/uploads.tar.gz" \
    --no-same-owner \
    --no-same-permissions \
    -C "${NEXT_DIR}/data"

# Resolve the production Compose file, retain only its environment, and build a
# constrained NAS Compose definition with a fixed local data mount and port.
docker compose -f "${BACKUP_DIR}/bookstark-compose.yml" config --format json > "${NEXT_DIR}/production-config.json"
python3 - \
    "${NEXT_DIR}/production-config.json" \
    "${NEXT_DIR}/compose.json" \
    "${IMAGE}" \
    "${CONTAINER_NAME}" \
    "${BIND_ADDRESS}" \
    "${PUBLISHED_PORT}" <<'PY'
import json
import pathlib
import sys

source_path, output_path, image, container_name, bind_address, published_port = sys.argv[1:]
source = json.loads(pathlib.Path(source_path).read_text())
services = source.get("services", {})
if set(services) != {"bookstark"}:
    raise SystemExit(f"unexpected production services: {sorted(services)}")
service = services["bookstark"]
if service.get("image") != image:
    raise SystemExit("production Compose image does not match backup manifest")
environment = dict(service.get("environment") or {})
environment.update({
    "DB_PATH": "/data/bookstark.db",
    "WEBDAV_DB_PATH": "/data/bookstark-webdav.db",
    "PORT": "8089",
    "MODE": "release",
    "TZ": environment.get("TZ") or "Asia/Shanghai",
})
standby = {
    "name": "bookstark-standby",
    "services": {
        "bookstark": {
            "image": image,
            "container_name": container_name,
            "environment": environment,
            "ports": [{
                "target": 8089,
                "published": str(published_port),
                "host_ip": bind_address,
                "protocol": "tcp",
            }],
            "volumes": [{
                "type": "bind",
                "source": "./data",
                "target": "/data",
            }],
            "restart": "unless-stopped",
            "logging": {
                "driver": "json-file",
                "options": {"max-size": "3m", "max-file": "1"},
            },
        }
    },
}
pathlib.Path(output_path).write_text(json.dumps(standby, ensure_ascii=False, indent=2) + "\n")
PY
rm -f -- "${NEXT_DIR}/production-config.json"
chmod 600 "${NEXT_DIR}/compose.json"
chown -R "${STANDBY_OWNER}" "${NEXT_DIR}"

compose() {
    local directory="$1"
    shift
    docker compose --project-name "${PROJECT_NAME}" -f "${directory}/compose.json" "$@"
}

# Validate the generated Compose file before stopping the old instance.
mapfile -t CONFIGURED_IMAGES < <(compose "${NEXT_DIR}" config --images)
if [ "${#CONFIGURED_IMAGES[@]}" -ne 1 ] || [ "${CONFIGURED_IMAGES[0]}" != "${IMAGE}" ]; then
    echo "Generated standby Compose contains an unexpected image." >&2
    exit 1
fi

if [ -f "${CURRENT_DIR}/compose.json" ]; then
    compose "${CURRENT_DIR}" down --remove-orphans
    OLD_DIR="$(mktemp -d "${STANDBY_ROOT}/.previous.XXXXXX")"
    rmdir "${OLD_DIR}"
    mv -- "${CURRENT_DIR}" "${OLD_DIR}"
fi
mv -- "${NEXT_DIR}" "${CURRENT_DIR}"
NEXT_DIR=""

if compose "${CURRENT_DIR}" up -d --remove-orphans; then
    HEALTHY=0
    for _ in $(seq 1 30); do
        if python3 - "${HEALTH_URL}" <<'PY'
import sys
import urllib.request

with urllib.request.urlopen(sys.argv[1], timeout=3) as response:
    if response.status < 200 or response.status >= 400:
        raise SystemExit(1)
PY
        then
            HEALTHY=1
            break
        fi
        sleep 2
    done
else
    HEALTHY=0
fi

if [ "${HEALTHY}" -ne 1 ]; then
    echo "The refreshed BookStark standby failed its health check; rolling back." >&2
    compose "${CURRENT_DIR}" logs --no-color --tail 100 >&2 || true
    compose "${CURRENT_DIR}" down --remove-orphans || true
    rm -rf -- "${CURRENT_DIR}"
    if [ -n "${OLD_DIR}" ] && [ -d "${OLD_DIR}" ]; then
        mv -- "${OLD_DIR}" "${CURRENT_DIR}"
        compose "${CURRENT_DIR}" up -d --remove-orphans
    fi
    exit 1
fi

if [ -n "${OLD_DIR}" ] && [ -d "${OLD_DIR}" ]; then
    rm -rf -- "${OLD_DIR}"
fi
printf 'BookStark NAS standby is healthy: %s (image %s)\n' "${HEALTH_URL}" "${IMAGE}"
