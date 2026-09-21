#!/usr/bin/env bash
set -euo pipefail
TUNNEL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${MCPCTL_HOME:-$(cd "$TUNNEL_DIR/.." && pwd)}"
ACTION="${1:-}"
INSTANCE="${2:-}"
[[ "$ACTION" == "run" || "$ACTION" == "doctor" ]] || { echo "usage: run.sh <run|doctor> <instance>" >&2; exit 2; }
[[ -n "$INSTANCE" ]] || { echo "instance is required" >&2; exit 2; }
ENV_FILE="$ROOT_DIR/instances/$INSTANCE/instance.env"
[[ -f "$ENV_FILE" ]] || { echo "instance not found: $INSTANCE" >&2; exit 1; }

read_env_value(){
  local file="$1" key="$2"
  awk -v k="$key" 'index($0,k"=")==1{sub(k"=",""); print; exit}' "$file"
}
for key in MCP_PORT MCP_AUTH_TOKEN TUNNEL_PROVIDER OPENAI_TUNNEL_ID OPENAI_RUNTIME_KEY_FILE CLOUDFLARE_MODE CLOUDFLARE_TOKEN_FILE; do
  value="$(read_env_value "$ENV_FILE" "$key" || true)"
  printf -v "$key" '%s' "$value"
  export "$key"
done

[[ "$MCP_PORT" =~ ^[0-9]+$ ]] || { echo "invalid MCP_PORT in $ENV_FILE" >&2; exit 1; }
[[ -n "$MCP_AUTH_TOKEN" ]] || { echo "missing MCP_AUTH_TOKEN in $ENV_FILE" >&2; exit 1; }
PROVIDER="${TUNNEL_PROVIDER:-none}"
[[ "$PROVIDER" != "none" ]] || { echo "tunnel disabled for $INSTANCE" >&2; exit 1; }
case "$PROVIDER" in
  openai|cloudflare) ;;
  *) echo "unsupported tunnel provider: $PROVIDER" >&2; exit 1 ;;
esac
PROVIDER_SCRIPT="$TUNNEL_DIR/providers/$PROVIDER.sh"
[[ -x "$PROVIDER_SCRIPT" ]] || { echo "provider script missing: $PROVIDER_SCRIPT" >&2; exit 1; }
export MCPCTL_HOME="$ROOT_DIR"
export MCP_INSTANCE="$INSTANCE"
export MCP_TARGET_URL="http://127.0.0.1:$MCP_PORT/mcp"
exec "$PROVIDER_SCRIPT" "$ACTION"
