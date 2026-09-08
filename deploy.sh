#!/usr/bin/env bash
set -euo pipefail


IMAGE="changhui/bookstark"
REMOTE="root@www.vs2010wy.top"
REMOTE_PORT=28246
COMPOSE_FILE="bookstark.yml"
SOURCE_ARCHIVE="$(mktemp -t bookstark-source.XXXXXX.tgz)"
trap 'rm -f "${SOURCE_ARCHIVE}"' EXIT

# Version from argument, fallback to latest git tag
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "latest")
fi

FULL_IMAGE="${IMAGE}:${VERSION}"

echo "=== Deploy BookStark ==="
echo "Image: ${FULL_IMAGE}"

# 1. Build & Push
echo ""
echo "[1/4] Building image..."
COMMIT="${COMMIT:-$(git rev-parse HEAD)}"
docker build --build-arg COMMIT="${COMMIT}" -t "${FULL_IMAGE}" .

echo ""
echo "[2/4] Pushing image..."
docker push "${FULL_IMAGE}"

# 2. Copy source archive
echo ""
echo "[3/4] Copying source archive..."
tar \
    --exclude='.git' \
    --exclude='bookstark/bookstark' \
    --exclude='bookstark/bookstark-dev' \
    --exclude='*.db' \
    --exclude='*.sqlite' \
    --exclude='*.sqlite3' \
    --exclude='bookstark.db*' \
    --exclude='bookstark/bookstark.db*' \
    --exclude='bookstark/.idea' \
    --exclude='*/.idea' \
    --exclude='bookstark/.vscode' \
    --exclude='*/.vscode' \
    --exclude='bookstark/node_modules' \
    --exclude='*/node_modules' \
    --exclude='bookstark/package.json' \
    --exclude='bookstark/package-lock.json' \
    --exclude='bookstark/pnpm-lock.yaml' \
    --exclude='bookstark/yarn.lock' \
    --exclude='bookstark/playwright-report' \
    --exclude='*/playwright-report' \
    --exclude='*.swp' \
    --exclude='*.swo' \
    --exclude='bookstark/.history' \
    --exclude='*/.history' \
    --exclude='.DS_Store' \
    --exclude='Thumbs.db' \
    --exclude='bookstark/.superpowers' \
    --exclude='*/.superpowers' \
    --exclude='bookstark/docs/superpowers' \
    --exclude='*/__pycache__' \
    --exclude='bookstark/tmp' \
    --exclude='*/tmp' \
    --exclude='bookstark/.tmp' \
    --exclude='*/.tmp' \
    --exclude='bookstark/test-results' \
    --exclude='*/test-results' \
    --exclude='bookstark/.playwright-mcp' \
    --exclude='*/.playwright-mcp' \
    --exclude='bookstark/.gstack' \
    --exclude='*/.gstack' \
    --exclude='bookstark/.omx' \
    --exclude='*/.omx' \
    --exclude='bookstark/.cc-connect' \
    --exclude='*/.cc-connect' \
    --exclude='bookstark/AGENTS.md' \
    --exclude='*/AGENTS.md' \
    --exclude='bookstark/*.log' \
    --exclude='*.log' \
    --exclude='bookstark/data' \
    --exclude='*/data' \
    --exclude='bookstark/key' \
    --exclude='bookstark/android/app/src/main/assets' \
    --exclude='bookstark/android/app/src/main/res/mipmap-mdpi' \
    --exclude='bookstark/android/app/src/main/res/mipmap-hdpi' \
    --exclude='bookstark/dist/android' \
    --exclude='*.tgz' \
    -czf "${SOURCE_ARCHIVE}" \
    -C "$(dirname "${PWD}")" \
    "$(basename "${PWD}")"
scp -P "${REMOTE_PORT}" "${SOURCE_ARCHIVE}" "${REMOTE}:/root/bookstark.tgz"

# 3. Remote deploy
echo ""
echo "[4/4] Deploying on remote server..."
ssh -p "${REMOTE_PORT}" "${REMOTE}" bash -s "${FULL_IMAGE}" "${COMPOSE_FILE}" <<'REMOTE_SCRIPT'
set -euo pipefail
IMAGE="$1"
COMPOSE_FILE="$2"

cd /root/docker

# Update image in compose file
sed -i "s|image: changhui/bookstark:.*|image: ${IMAGE}|" "${COMPOSE_FILE}"


echo "Updated ${COMPOSE_FILE} -> image: ${IMAGE}"

# Restart service
docker compose -f "${COMPOSE_FILE}" pull
docker compose -f "${COMPOSE_FILE}" up -d


echo "=== Deploy complete: ${IMAGE} ==="
REMOTE_SCRIPT

echo ""
echo "Done! ${FULL_IMAGE} deployed."
