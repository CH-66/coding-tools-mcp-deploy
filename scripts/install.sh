#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-/opt/coding-tools-mcp}"
BIN_LINK="${BIN_LINK:-/usr/local/bin/mcpctl}"
MCP_GATEWAY_AUTO_START="${MCP_GATEWAY_AUTO_START:-on}"

[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "run with sudo/root" >&2; exit 1; }
source "$SOURCE_DIR/config/versions.env"

if command -v docker >/dev/null 2>&1; then
  echo "Using existing Docker: $(docker --version 2>/dev/null || command -v docker)"
else
  echo "Docker not found. Installing bundled Docker Engine $DOCKER_ENGINE_VERSION ..."
  bash "$SOURCE_DIR/scripts/install-docker.sh"     "$SOURCE_DIR/offline/docker/docker-$DOCKER_ENGINE_VERSION.tgz"     "$SOURCE_DIR/systemd/docker.service"
fi

docker info >/dev/null 2>&1 || {
  echo "Docker command exists but daemon is unavailable; existing Docker will not be overwritten." >&2
  exit 1
}
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }

mkdir -p "$INSTALL_DIR"/{bin,compose,config,instances,tunnel/providers,systemd,gateway/data/etcd}
cp "$SOURCE_DIR/bin/mcpctl" "$INSTALL_DIR/bin/mcpctl"
cp "$SOURCE_DIR/compose/docker-compose.yml" "$INSTALL_DIR/compose/docker-compose.yml"
cp "$SOURCE_DIR/compose/gateway-compose.yml" "$INSTALL_DIR/compose/gateway-compose.yml"
cp "$SOURCE_DIR/config/versions.env" "$INSTALL_DIR/config/versions.env"
cp "$SOURCE_DIR/tunnel/run.sh" "$INSTALL_DIR/tunnel/run.sh"
cp "$SOURCE_DIR/tunnel/providers/"*.sh "$INSTALL_DIR/tunnel/providers/"
cp "$SOURCE_DIR/systemd/coding-tools-tunnel@.service" "$INSTALL_DIR/systemd/"
cp "$SOURCE_DIR/gateway/config.yaml.tpl" "$INSTALL_DIR/gateway/config.yaml.tpl"
chmod 755 "$INSTALL_DIR/bin/mcpctl" "$INSTALL_DIR/tunnel/run.sh" "$INSTALL_DIR/tunnel/providers/"*.sh
chmod 700 "$INSTALL_DIR/instances" "$INSTALL_DIR/gateway"

ln -sfn "$INSTALL_DIR/bin/mcpctl" "$BIN_LINK"

for b in tunnel-client cloudflared docker-compose; do
  [[ -f "$SOURCE_DIR/offline/bin/$b" ]] && install -m 755 "$SOURCE_DIR/offline/bin/$b" "$INSTALL_DIR/bin/$b"
done

if [[ -x "$INSTALL_DIR/bin/docker-compose" ]]; then
  "$INSTALL_DIR/bin/docker-compose" version >/dev/null
elif docker compose version >/dev/null 2>&1; then
  :
elif command -v docker-compose >/dev/null 2>&1; then
  docker-compose version >/dev/null
else
  echo "docker compose unavailable and bundled offline/bin/docker-compose is missing" >&2
  exit 1
fi

shopt -s nullglob
for image in "$SOURCE_DIR"/offline/images/*.tar; do
  echo "Loading $image"
  docker load -i "$image"
done
shopt -u nullglob

source "$INSTALL_DIR/config/versions.env"
ADMIN_KEY_FILE="$INSTALL_DIR/gateway/admin.key"
if [[ ! -s "$ADMIN_KEY_FILE" ]]; then
  if command -v openssl >/dev/null 2>&1; then
    ADMIN_KEY="$(openssl rand -hex 32)"
  else
    ADMIN_KEY="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
  fi
  (umask 077; printf '%s\n' "$ADMIN_KEY" > "$ADMIN_KEY_FILE")
  unset ADMIN_KEY
fi
chmod 600 "$ADMIN_KEY_FILE"
ADMIN_KEY="$(cat "$ADMIN_KEY_FILE")"
sed   -e "s/__APISIX_ADMIN_KEY__/$ADMIN_KEY/g"   -e "s/__APISIX_GATEWAY_PORT__/$APISIX_GATEWAY_PORT/g"   -e "s/__APISIX_ADMIN_PORT__/$APISIX_ADMIN_PORT/g"   -e "s/__ETCD_CLIENT_PORT__/$ETCD_CLIENT_PORT/g"   "$INSTALL_DIR/gateway/config.yaml.tpl" > "$INSTALL_DIR/gateway/config.yaml"
chmod 600 "$INSTALL_DIR/gateway/config.yaml"
unset ADMIN_KEY

if [[ "$INSTALL_DIR" == /opt/coding-tools-mcp ]] && command -v systemctl >/dev/null 2>&1; then
  cp "$SOURCE_DIR/systemd/coding-tools-tunnel@.service" /etc/systemd/system/coding-tools-tunnel@.service
  systemctl daemon-reload
fi

echo "Installed at $INSTALL_DIR"
"$INSTALL_DIR/bin/mcpctl" version

if [[ "$MCP_GATEWAY_AUTO_START" != "off" ]]; then
  "$INSTALL_DIR/bin/mcpctl" gateway up
else
  echo "APISIX gateway auto-start disabled (MCP_GATEWAY_AUTO_START=off)"
fi
