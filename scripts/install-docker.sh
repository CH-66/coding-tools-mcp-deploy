#!/usr/bin/env bash
set -euo pipefail

ARCHIVE="${1:-}"
UNIT_FILE="${2:-}"

[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "run with sudo/root" >&2; exit 1; }

if command -v docker >/dev/null 2>&1; then
  echo "Docker already exists: $(docker --version 2>/dev/null || command -v docker)"
  echo "Skip bundled offline Docker installation."
  exit 0
fi

[[ -n "$ARCHIVE" && -f "$ARCHIVE" ]] || { echo "offline Docker archive not found: $ARCHIVE" >&2; exit 1; }
[[ -n "$UNIT_FILE" && -f "$UNIT_FILE" ]] || { echo "Docker systemd unit not found: $UNIT_FILE" >&2; exit 1; }

for c in tar systemctl iptables; do
  command -v "$c" >/dev/null 2>&1 || { echo "$c is required to install bundled Docker" >&2; exit 1; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

tar -xzf "$ARCHIVE" -C "$TMP"
[[ -x "$TMP/docker/docker" && -x "$TMP/docker/dockerd" ]] || {
  echo "invalid offline Docker archive" >&2
  exit 1
}

for binary in "$TMP"/docker/*; do
  [[ -f "$binary" ]] || continue
  install -m 755 "$binary" "/usr/local/bin/$(basename "$binary")"
done

install -d -m 755 /etc/docker /var/lib/docker
install -m 644 "$UNIT_FILE" /etc/systemd/system/docker.service

systemctl daemon-reload
systemctl enable --now docker.service

for _ in $(seq 1 30); do
  if /usr/local/bin/docker info >/dev/null 2>&1; then
    echo "Bundled Docker installed: $(/usr/local/bin/docker --version)"
    exit 0
  fi
  sleep 1
done

systemctl status docker.service --no-pager || true
echo "bundled Docker daemon did not become ready" >&2
exit 1
