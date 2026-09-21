#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-/opt/coding-tools-mcp}"
BIN_LINK="${BIN_LINK:-/usr/local/bin/mcpctl}"

[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "run with sudo/root" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "docker daemon unavailable" >&2; exit 1; }

mkdir -p "$INSTALL_DIR"/{bin,compose,config,instances,tunnel/providers,systemd}
cp "$SOURCE_DIR/bin/mcpctl" "$INSTALL_DIR/bin/mcpctl"
cp "$SOURCE_DIR/compose/docker-compose.yml" "$INSTALL_DIR/compose/docker-compose.yml"
cp "$SOURCE_DIR/config/versions.env" "$INSTALL_DIR/config/versions.env"
cp "$SOURCE_DIR/tunnel/run.sh" "$INSTALL_DIR/tunnel/run.sh"
cp "$SOURCE_DIR/tunnel/providers/"*.sh "$INSTALL_DIR/tunnel/providers/"
cp "$SOURCE_DIR/systemd/coding-tools-tunnel@.service" "$INSTALL_DIR/systemd/"
chmod 755 "$INSTALL_DIR/bin/mcpctl" "$INSTALL_DIR/tunnel/run.sh" "$INSTALL_DIR/tunnel/providers/"*.sh
chmod 700 "$INSTALL_DIR/instances"
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

if [[ "$INSTALL_DIR" == /opt/coding-tools-mcp ]] && command -v systemctl >/dev/null 2>&1; then
  cp "$SOURCE_DIR/systemd/coding-tools-tunnel@.service" /etc/systemd/system/coding-tools-tunnel@.service
  systemctl daemon-reload
fi

echo "Installed at $INSTALL_DIR"
"$INSTALL_DIR/bin/mcpctl" version
