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
BUILD_SWAP_MAX="${BUILD_SWAP_MAX:-1G}"
BUILD_CPU_QUOTA="${BUILD_CPU_QUOTA:-100%}"
BUILD_GO_MEMORY="${BUILD_GO_MEMORY:-300MiB}"
# systemd enforces the hard limit on the compiler and all its children.
for tool in docker git ssh tar; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
if ! command -v go >/dev/null && [ -x /usr/local/go/bin/go ]; then
    export PATH="/usr/local/go/bin:$PATH"
fi
if command -v go >/dev/null; then
    BUILD_MODE="native"
    for tool in systemd-run python3; do
        command -v "$tool" >/dev/null || { echo "Missing tool for native build: $tool" >&2; exit 1; }
    done
else
    BUILD_MODE="docker"
fi

# Deploy only a clean, named branch with a configured source remote.
GIT_REMOTE="${GIT_REMOTE:-origin}"
GIT_BRANCH="$(git symbolic-ref --quiet --short HEAD)" || {
    echo "Deployment requires a branch checkout (not detached HEAD)." >&2; exit 1;
}
git remote get-url "${GIT_REMOTE}" >/dev/null
if [ -n "$(git status --porcelain --untracked-files=normal)" ]; then
    echo "Deployment requires a clean worktree. Commit or remove all changes first:" >&2
    git status --short >&2
    exit 1
fi

# This exact revision is used for the source push, binary metadata, immutable
# build snapshot and container image label. Never accept an external override.
COMMIT="$(git rev-parse HEAD)"

IMAGE="changhui/bookstark"
REMOTE="root@www.vs2010wy.top"
REMOTE_PORT=28246
COMPOSE_FILE="bookstark.yml"
BUILD_DIR="$(mktemp -d -t bookstark-release.XXXXXX)"
trap 'rm -rf -- "${BUILD_DIR}"' EXIT
SOURCE_DIR="${BUILD_DIR}/source"
ARTIFACT_DIR="${BUILD_DIR}/artifacts"
mkdir -p "${SOURCE_DIR}" "${ARTIFACT_DIR}"

# Version from argument, otherwise use an exact tag at HEAD or an immutable
# commit-derived tag. Never reuse an unrelated historical tag or "latest".
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    VERSION="$(git tag --points-at "${COMMIT}" --sort=-version:refname | head -n 1)"
fi
if [ -z "$VERSION" ]; then
    VERSION="git-${COMMIT:0:12}"
fi
if [[ ! "$VERSION" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
    echo "Invalid Docker image tag: ${VERSION}" >&2
    exit 1
fi

FULL_IMAGE="${IMAGE}:${VERSION}"

echo "=== Deploy BookStark ==="
echo "Image: ${FULL_IMAGE}"

# 1. Publish the exact source revision before producing an image.
echo ""
echo "[1/4] Publishing source revision ${COMMIT}..."
git push --set-upstream "${GIT_REMOTE}" "HEAD:${GIT_BRANCH}"
REMOTE_COMMIT="$(git ls-remote "${GIT_REMOTE}" "refs/heads/${GIT_BRANCH}" | awk '{print $1}')"
if [ "$REMOTE_COMMIT" != "$COMMIT" ]; then
    echo "Remote ${GIT_REMOTE}/${GIT_BRANCH} is ${REMOTE_COMMIT:-missing}, expected ${COMMIT}." >&2
    exit 1
fi

# Build from an immutable archive so build.py can regenerate sw.js and asset
# hashes without changing the checkout that was just pushed.
git archive --format=tar "${COMMIT}" | tar -xf - -C "${SOURCE_DIR}"

# 2. Build the binary and image from that exact snapshot.
echo ""
echo "[2/4] Building image from ${COMMIT} (${BUILD_MODE})..."
if [ "$BUILD_MODE" = native ]; then
    # Do not compile in docker build: BuildKit does not inherit this shell's
    # systemd cgroup. --wait propagates build/OOM failure.
    systemd-run --quiet --wait --pipe --collect \
        --unit="bookstark-deploy-build" \
        --working-directory="${SOURCE_DIR}" \
        --property="MemoryMax=${BUILD_MEMORY_MAX}" \
        --property="MemoryHigh=${BUILD_MEMORY_HIGH}" \
        --property="MemorySwapMax=${BUILD_SWAP_MAX}" \
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
        python3 -u build.py --build --tags timetzdata --output "${ARTIFACT_DIR}/bookstark"

    # The Docker stage only copies the finished binary; no second compilation.
    cp /etc/ssl/certs/ca-certificates.crt "${ARTIFACT_DIR}/ca-certificates.crt"
    docker build \
        --build-arg "COMMIT=${COMMIT}" \
        -f "${PWD}/Dockerfile.release" \
        -t "${FULL_IMAGE}" \
        "${ARTIFACT_DIR}"
else
    # Hosts without Go can still produce the same revision-labelled image via
    # the repository's multi-stage build. The source snapshot remains exact.
    docker build \
        --build-arg "COMMIT=${COMMIT}" \
        -f "${SOURCE_DIR}/Dockerfile" \
        -t "${FULL_IMAGE}" \
        "${SOURCE_DIR}"
fi

echo ""
echo "[3/4] Transferring image (${DEPLOY_TRANSPORT})..."
if [ "$DEPLOY_TRANSPORT" = ssh ]; then
    docker save "${FULL_IMAGE}" | gzip -1 | ssh -p "${REMOTE_PORT}" "${REMOTE}" 'gunzip | docker load'
else
    docker push "${FULL_IMAGE}"
fi

# 4. Remote deploy and verify the image revision.
echo ""
echo "[4/4] Deploying on remote server..."
ssh -p "${REMOTE_PORT}" "${REMOTE}" bash -s "${FULL_IMAGE}" "${COMPOSE_FILE}" "${DEPLOY_TRANSPORT}" "${COMMIT}" <<'REMOTE_SCRIPT'
set -euo pipefail
IMAGE="$1"
COMPOSE_FILE="$2"
DEPLOY_TRANSPORT="$3"
EXPECTED_COMMIT="$4"

cd /root/docker

# Update image in compose file
sed -i "s|image: changhui/bookstark:.*|image: ${IMAGE}|" "${COMPOSE_FILE}"


echo "Updated ${COMPOSE_FILE} -> image: ${IMAGE}"

# Restart service
if [ "$DEPLOY_TRANSPORT" = registry ]; then
    docker compose -f "${COMPOSE_FILE}" pull bookstark
fi
docker compose -f "${COMPOSE_FILE}" up -d --no-deps bookstark

RUNNING_IMAGE="$(docker inspect bookstark --format '{{.Config.Image}}')"
RUNNING_COMMIT="$(docker inspect bookstark --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')"
if [ "$RUNNING_IMAGE" != "$IMAGE" ] || [ "$RUNNING_COMMIT" != "$EXPECTED_COMMIT" ]; then
    echo "Deployment verification failed: image=${RUNNING_IMAGE}, revision=${RUNNING_COMMIT}" >&2
    exit 1
fi

echo "=== Deploy complete: ${IMAGE} (${RUNNING_COMMIT}) ==="
REMOTE_SCRIPT

echo ""
echo "Done! ${FULL_IMAGE} deployed from ${COMMIT}."
