#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HOME_DIR="$TMP/install"
FAKE_BIN="$TMP/fake-bin"
mkdir -p "$HOME_DIR"/{bin,compose,config,instances/demo,gateway/data/etcd} "$FAKE_BIN"

cp "$ROOT/bin/mcpctl" "$HOME_DIR/bin/mcpctl"
cp "$ROOT/config/versions.env" "$HOME_DIR/config/versions.env"
cp "$ROOT/compose/docker-compose.yml" "$HOME_DIR/compose/docker-compose.yml"
cp "$ROOT/compose/gateway-compose.yml" "$HOME_DIR/compose/gateway-compose.yml"
chmod 755 "$HOME_DIR/bin/mcpctl"

cat > "$HOME_DIR/bin/docker-compose" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod 755 "$HOME_DIR/bin/docker-compose"

cat > "$FAKE_BIN/docker" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == inspect ]]; then
  echo true
  exit 0
fi
exit 0
STUB
chmod 755 "$FAKE_BIN/docker"

cat > "$FAKE_BIN/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
: "${CURL_LOG:?}"
printf '%s\n' "$@" > "$CURL_LOG"
for arg in "$@"; do
  if [[ "$arg" == '%{http_code}' ]]; then
    printf '200'
    exit 0
  fi
done
exit 0
STUB
chmod 755 "$FAKE_BIN/curl"

cat > "$HOME_DIR/gateway/config.yaml" <<'YAML'
deployment:
  admin:
    admin_key:
      - name: admin
        key: test-admin-key
        role: admin
YAML
printf '%s\n' 'test-admin-key' > "$HOME_DIR/gateway/admin.key"
chmod 600 "$HOME_DIR/gateway/admin.key" "$HOME_DIR/gateway/config.yaml"

workspace="$TMP/workspace"
mkdir -p "$workspace"
cat > "$HOME_DIR/instances/demo/instance.env" <<ENV
INSTANCE_NAME=demo
WORKSPACE_DIR=$workspace
MCP_PORT=19991
MCP_IMAGE=coding-tools-mcp:0.3.0
MCP_PERMISSION_MODE=trusted
MCP_TELEMETRY=off
MCP_AUTH_TOKEN=test-token
MCP_GATEWAY=direct
TUNNEL_PROVIDER=none
ENV
chmod 600 "$HOME_DIR/instances/demo/instance.env"

export PATH="$FAKE_BIN:$PATH"
export CURL_LOG="$TMP/curl.log"

MCPCTL_HOME="$HOME_DIR" bash "$ROOT/bin/mcpctl" gateway route demo

grep -q '^MCP_GATEWAY=apisix$' "$HOME_DIR/instances/demo/instance.env"
grep -q '/apisix/admin/routes/mcp-demo' "$CURL_LOG"
grep -q '"uri": "/mcp/demo"' "$CURL_LOG"
grep -q '"127.0.0.1:19991": 1' "$CURL_LOG"
grep -q '"proxy-buffering"' "$CURL_LOG"
grep -q '"disable_proxy_buffering": true' "$CURL_LOG"

MCPCTL_HOME="$HOME_DIR" bash "$ROOT/bin/mcpctl" gateway unroute demo

grep -q '^MCP_GATEWAY=direct$' "$HOME_DIR/instances/demo/instance.env"
grep -q '/apisix/admin/routes/mcp-demo' "$CURL_LOG"
grep -q '^DELETE$' "$CURL_LOG"

echo "gateway route tests passed"
