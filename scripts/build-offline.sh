#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/config/versions.env"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) PKG_ARCH=amd64; COMPOSE_ARCH=x86_64 ;;
  aarch64|arm64) PKG_ARCH=arm64; COMPOSE_ARCH=aarch64 ;;
  *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac

for c in git docker curl unzip tar sha256sum awk; do
  command -v "$c" >/dev/null 2>&1 || { echo "$c is required on build machine" >&2; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "docker daemon unavailable" >&2; exit 1; }

BUILD="$ROOT_DIR/.build"
STAGE="$BUILD/stage/coding-tools-mcp-deploy-$DEPLOY_VERSION"
UPSTREAM="$BUILD/coding-tools-mcp"
DIST="$ROOT_DIR/dist"
rm -rf "$BUILD"
mkdir -p "$STAGE/offline/bin" "$STAGE/offline/images" "$DIST"

git clone --depth 1 --branch "$CODING_TOOLS_MCP_REF" https://github.com/xyTom/coding-tools-mcp.git "$UPSTREAM"
docker build -t "$MCP_IMAGE" "$UPSTREAM"
docker save -o "$STAGE/offline/images/coding-tools-mcp-$CODING_TOOLS_MCP_VERSION.tar" "$MCP_IMAGE"

echo "Pulling APISIX gateway images for native architecture: $PKG_ARCH"
docker pull "$APISIX_IMAGE"
docker save -o "$STAGE/offline/images/apache-apisix-$APISIX_VERSION.tar" "$APISIX_IMAGE"
docker pull "$ETCD_IMAGE"
docker save -o "$STAGE/offline/images/etcd-$ETCD_VERSION.tar" "$ETCD_IMAGE"

OPENAI_ZIP="tunnel-client-$OPENAI_TUNNEL_CLIENT_VERSION-linux-$PKG_ARCH.zip"
OPENAI_URL="https://github.com/openai/tunnel-client/releases/download/$OPENAI_TUNNEL_CLIENT_VERSION/$OPENAI_ZIP"
mkdir -p "$BUILD/openai"
curl -fL --retry 3 -o "$BUILD/$OPENAI_ZIP" "$OPENAI_URL"
unzip -q "$BUILD/$OPENAI_ZIP" -d "$BUILD/openai"
OPENAI_BIN="$(find "$BUILD/openai" -type f -name tunnel-client | head -n1)"
[[ -n "$OPENAI_BIN" ]] || { echo "tunnel-client binary not found" >&2; exit 1; }
install -m 755 "$OPENAI_BIN" "$STAGE/offline/bin/tunnel-client"

CF_URL="https://github.com/cloudflare/cloudflared/releases/download/$CLOUDFLARED_VERSION/cloudflared-linux-$PKG_ARCH"
curl -fL --retry 3 -o "$STAGE/offline/bin/cloudflared" "$CF_URL"
chmod 755 "$STAGE/offline/bin/cloudflared"

COMPOSE_ASSET="docker-compose-linux-$COMPOSE_ARCH"
COMPOSE_URL="https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/$COMPOSE_ASSET"
COMPOSE_SHA_URL="$COMPOSE_URL.sha256"
curl -fL --retry 3 -o "$STAGE/offline/bin/docker-compose" "$COMPOSE_URL"
curl -fL --retry 3 -o "$BUILD/$COMPOSE_ASSET.sha256" "$COMPOSE_SHA_URL"
EXPECTED_COMPOSE_SHA="$(awk '{print $1; exit}' "$BUILD/$COMPOSE_ASSET.sha256")"
ACTUAL_COMPOSE_SHA="$(sha256sum "$STAGE/offline/bin/docker-compose" | awk '{print $1}')"
[[ -n "$EXPECTED_COMPOSE_SHA" && "$ACTUAL_COMPOSE_SHA" == "$EXPECTED_COMPOSE_SHA" ]] || {
  echo "docker-compose checksum mismatch: expected=$EXPECTED_COMPOSE_SHA actual=$ACTUAL_COMPOSE_SHA" >&2
  exit 1
}
chmod 755 "$STAGE/offline/bin/docker-compose"
"$STAGE/offline/bin/docker-compose" version >/dev/null

for path in README.md LICENSE Makefile bin compose config docs gateway scripts tunnel systemd; do
  cp -a "$ROOT_DIR/$path" "$STAGE/"
done
mkdir -p "$STAGE/instances"
(cd "$STAGE" && find . -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)

PACKAGE="$DIST/coding-tools-mcp-deploy-$DEPLOY_VERSION-linux-$PKG_ARCH.tgz"
tar -C "$(dirname "$STAGE")" -czf "$PACKAGE" "$(basename "$STAGE")"
echo "Built: $PACKAGE"
