#!/usr/bin/env bash
set -euo pipefail
ACTION="${1:-}"
ROOT_DIR="${MCPCTL_HOME:?MCPCTL_HOME is required}"
INSTANCE="${MCP_INSTANCE:?MCP_INSTANCE is required}"
TARGET_URL="${MCP_TARGET_URL:?MCP_TARGET_URL is required}"
BIN="$ROOT_DIR/bin/cloudflared"
[[ -x "$BIN" ]] || { echo "cloudflared not installed: $BIN" >&2; exit 1; }
MODE="${CLOUDFLARE_MODE:-token}"
case "$ACTION" in
  run)
    case "$MODE" in
      token)
        TOKEN_FILE="${CLOUDFLARE_TOKEN_FILE:-$ROOT_DIR/instances/$INSTANCE/secrets/cloudflare_token}"
        [[ -s "$TOKEN_FILE" ]] || { echo "Cloudflare token file missing: $TOKEN_FILE" >&2; exit 1; }
        echo "Cloudflare public hostname must route to http://127.0.0.1:$MCP_PORT" >&2
        exec "$BIN" tunnel --no-autoupdate run --token-file "$TOKEN_FILE"
        ;;
      quick) exec "$BIN" tunnel --no-autoupdate --url "$TARGET_URL" ;;
      *) echo "unsupported CLOUDFLARE_MODE: $MODE" >&2; exit 1 ;;
    esac
    ;;
  doctor)
    "$BIN" --version
    curl -fsS -o /dev/null -H "Authorization: Bearer $MCP_AUTH_TOKEN"       -H 'Accept: application/json, text/event-stream'       -H 'Content-Type: application/json'       --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"mcpctl-cf-doctor","version":"0.1"}}}'       "$TARGET_URL"
    ;;
  *) echo "usage: cloudflare.sh <run|doctor>" >&2; exit 2 ;;
esac
