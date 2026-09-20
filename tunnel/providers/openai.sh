#!/usr/bin/env bash
set -euo pipefail
ACTION="${1:-}"
ROOT_DIR="${MCPCTL_HOME:?MCPCTL_HOME is required}"
INSTANCE="${MCP_INSTANCE:?MCP_INSTANCE is required}"
TARGET_URL="${MCP_TARGET_URL:?MCP_TARGET_URL is required}"
BIN="$ROOT_DIR/bin/tunnel-client"
[[ -x "$BIN" ]] || { echo "OpenAI tunnel-client not installed: $BIN" >&2; exit 1; }
[[ -n "${OPENAI_TUNNEL_ID:-}" ]] || { echo "OPENAI_TUNNEL_ID is not configured for $INSTANCE" >&2; exit 1; }
KEY_FILE="${OPENAI_RUNTIME_KEY_FILE:-$ROOT_DIR/instances/$INSTANCE/secrets/openai_runtime_key}"
[[ -s "$KEY_FILE" ]] || { echo "OpenAI runtime key file missing: $KEY_FILE" >&2; exit 1; }
export CONTROL_PLANE_API_KEY="$(cat "$KEY_FILE")"
export CONTROL_PLANE_TUNNEL_ID="$OPENAI_TUNNEL_ID"
export MCP_SERVER_URL="$TARGET_URL"
export LOCAL_MCP_AUTH_HEADER="Bearer $MCP_AUTH_TOKEN"
export MCP_EXTRA_HEADERS="Authorization: env:LOCAL_MCP_AUTH_HEADER"
export MCP_DISCOVERY_EXTRA_HEADERS="Authorization: env:LOCAL_MCP_AUTH_HEADER"
case "$ACTION" in
  run) exec "$BIN" run --health.listen-addr 127.0.0.1:0 ;;
  doctor) exec "$BIN" doctor --explain ;;
  *) echo "usage: openai.sh <run|doctor>" >&2; exit 2 ;;
esac
