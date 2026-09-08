#!/usr/bin/env bash
set -euo pipefail


# Always operate on this checkout, even when invoked from another directory.
cd "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Serialize deployments on this small build host.
exec 9>"/tmp/bookstark-deploy-${UID}.lock"
flock -n 9 || { echo "Another BookStark deployment is running." >&2; exit 1; }

DEPLOY_TRANSPORT="${DEPLOY_TRANSPORT:-registry}"
case "$DEPLOY_TRANSPORT" in
    registry|ssh) ;;
    *) echo "DEPLOY_TRANSPORT must be registry or ssh" >&2; exit 1 ;;
esac

BUILD_MEMORY_MAX="${BUILD_MEMORY_MAX:-850M}"
BUILD_MEMORY_HIGH="${BUILD_MEMORY_HIGH:-700M}"
BUILD_CPU_QUOTA="${BUILD_CPU_QUOTA:-100%}"
BUILD_GO_MEMORY="${BUILD_GO_MEMORY:-300MiB}"
# systemd enforces the hard limit on the compiler and all its children.
for tool in systemd-run docker git python3 ssh scp; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
if ! command -v go >/dev/null && [ -x /usr/local/go/bin/go ]; then
    export PATH="/usr/local/go/bin:$PATH"
fi
command -v go >/dev/null || { echo "Go is required for the limited local build." >&2; exit 1; }

IMAGE="changhui/bookstark"
REMOTE="root@www.vs2010wy.top"
REMOTE_PORT=28246
COMPOSE_FILE="bookstark.yml"
BUILD_DIR="$(mktemp -d -t bookstark-release.XXXXXX)"
SOURCE_ARCHIVE="${BUILD_DIR}/bookstark.tgz"
trap 'rm -rf -- "${BUILD_DIR}"' EXIT

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
# Do not compile in docker build: BuildKit does not inherit this shell's cgroup.
# --wait propagates build/OOM failure, so no upload or deployment follows failure.
systemd-run --quiet --wait --pipe --collect \
    --unit="bookstark-deploy-build" \
    --working-directory="$PWD" \
    --property="MemoryMax=${BUILD_MEMORY_MAX}" \
    --property="MemoryHigh=${BUILD_MEMORY_HIGH}" \
    --property="MemorySwapMax=0" \
    --property="CPUQuota=${BUILD_CPU_QUOTA}" \
    --setenv="PATH=$PATH" \
    --setenv="GOPATH=$(go env GOPATH)" \
    --setenv="GOCACHE=$(go env GOCACHE)" \
    --setenv="GOPROXY=$(go env GOPROXY)" \
    --setenv="GOFLAGS=-p=1" \
    --setenv="GOMAXPROCS=1" \
    --setenv="GOMEMLIMIT=${BUILD_GO_MEMORY}" \
    --setenv="CGO_ENABLED=0" \
    --setenv="COMMIT=${COMMIT}" \
    python3 -u build.py --build --tags timetzdata --output "${BUILD_DIR}/bookstark"

# The Docker stage only copies the finished binary; no second compilation.
cp /etc/ssl/certs/ca-certificates.crt "${BUILD_DIR}/ca-certificates.crt"
docker build -f Dockerfile.release -t "${FULL_IMAGE}" "${BUILD_DIR}"

echo ""
echo "[2/4] Transferring image (${DEPLOY_TRANSPORT})..."
if [ "$DEPLOY_TRANSPORT" = ssh ]; then
    docker save "${FULL_IMAGE}" | gzip -1 | ssh -p "${REMOTE_PORT}" "${REMOTE}" 'gunzip | docker load'
else
    docker push "${FULL_IMAGE}"
fi

# 2. Copy source archive
echo ""
echo "[3/4] Copying source archive..."
tar \
    --exclude='.git' \
    --exclude='bookstark/bookstark' \
    --exclude='bookstark/bookstark-dev' \
    --exclude='bookstark/dist/bookstark' \
    --exclude='*.db' \
    --exclude='*.db-*' \
    --exclude='*.sqlite-*' \
    --exclude='*.sqlite3-*' \
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
ssh -p "${REMOTE_PORT}" "${REMOTE}" bash -s "${FULL_IMAGE}" "${COMPOSE_FILE}" "${DEPLOY_TRANSPORT}" <<'REMOTE_SCRIPT'
set -euo pipefail
IMAGE="$1"
COMPOSE_FILE="$2"
DEPLOY_TRANSPORT="$3"

cd /root/docker

# Update image in compose file
sed -i "s|image: changhui/bookstark:.*|image: ${IMAGE}|" "${COMPOSE_FILE}"


echo "Updated ${COMPOSE_FILE} -> image: ${IMAGE}"

# Restart service
if [ "$DEPLOY_TRANSPORT" = registry ]; then
    docker compose -f "${COMPOSE_FILE}" pull bookstark
fi
docker compose -f "${COMPOSE_FILE}" up -d --no-deps bookstark


echo "=== Deploy complete: ${IMAGE} ==="
REMOTE_SCRIPT

echo ""
echo "Done! ${FULL_IMAGE} deployed."
