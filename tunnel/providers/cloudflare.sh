#!/usr/bin/env bash
set -euo pipefail
ACTION="${1:-}"
ROOT_DIR="${MCPCTL_HOME:?MCPCTL_HOME is required}"
INSTANCE="${MCP_INSTANCE:?MCP_INSTANCE is required}"
TARGET_URL="${MCP_TARGET_URL:?MCP_TARGET_URL is required}"
DIRECT_URL="${MCP_DIRECT_URL:-$TARGET_URL}"
BIN="$ROOT_DIR/bin/cloudflared"
[[ -x "$BIN" ]] || { echo "cloudflared not installed: $BIN" >&2; exit 1; }
MODE="${CLOUDFLARE_MODE:-token}"
case "$ACTION" in
  run)
    case "$MODE" in
      token)
        TOKEN_FILE="${CLOUDFLARE_TOKEN_FILE:-$ROOT_DIR/instances/$INSTANCE/secrets/cloudflare_token}"
        [[ -s "$TOKEN_FILE" ]] || { echo "Cloudflare token file missing: $TOKEN_FILE" >&2; exit 1; }
        if [[ "${MCP_GATEWAY:-direct}" == apisix ]]; then
          echo "Cloudflare Published application must route to http://127.0.0.1:$APISIX_GATEWAY_PORT; external MCP path is /mcp/$INSTANCE" >&2
        else
          echo "Cloudflare public hostname must route to http://127.0.0.1:$MCP_PORT" >&2
        fi
        exec "$BIN" tunnel --no-autoupdate run --token-file "$TOKEN_FILE"
        ;;
      quick)
        # Quick Tunnel stays direct. This avoids relying on cloudflared origin-path
        # behavior and preserves the familiar public /mcp endpoint.
        exec "$BIN" tunnel --no-autoupdate --url "$DIRECT_URL"
        ;;
      *) echo "unsupported CLOUDFLARE_MODE: $MODE" >&2; exit 1 ;;
    esac
    ;;
  doctor)
    "$BIN" --version
    curl -fsS -o /dev/null -H "Authorization: Bearer $MCP_AUTH_TOKEN" \
      -H 'Accept: application/json, text/event-stream' \
      -H 'Content-Type: application/json' \
      --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"mcpctl-cf-doctor","version":"2.0"}}}' \
      "$TARGET_URL"
    ;;
  *) echo "usage: cloudflare.sh <run|doctor>" >&2; exit 2 ;;
esac
