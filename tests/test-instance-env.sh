#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HOME_DIR="$TMP/install"
mkdir -p "$HOME_DIR"/{bin,compose,config,instances,tunnel/providers}
cp "$ROOT/config/versions.env" "$HOME_DIR/config/versions.env"
cp "$ROOT/compose/docker-compose.yml" "$HOME_DIR/compose/docker-compose.yml"

cat > "$HOME_DIR/bin/docker-compose" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${EXPECTED_WORKSPACE:-}" != "${WORKSPACE_DIR:-}" ]]; then
  echo "WORKSPACE_DIR mismatch" >&2
  printf 'expected=%q\nactual=%q\n' "${EXPECTED_WORKSPACE:-}" "${WORKSPACE_DIR:-}" >&2
  exit 1
fi
exit 0
STUB
chmod 755 "$HOME_DIR/bin/docker-compose"

workspace="$TMP/workspace ; touch PWNED"
mkdir -p "$workspace"
export EXPECTED_WORKSPACE="$workspace"

(
  cd "$TMP"
  MCPCTL_HOME="$HOME_DIR" "$ROOT/bin/mcpctl" add safe-test "$workspace" 19991
)
[[ ! -e "$TMP/PWNED" ]]
grep -q '^WORKSPACE_DIR_B64=' "$HOME_DIR/instances/safe-test/instance.env"
! grep -q '^WORKSPACE_DIR=' "$HOME_DIR/instances/safe-test/instance.env"

mkdir -p "$HOME_DIR/instances/legacy"
cat > "$HOME_DIR/instances/legacy/instance.env" <<ENV
INSTANCE_NAME=legacy
WORKSPACE_DIR=$workspace
MCP_PORT=19992
MCP_IMAGE=coding-tools-mcp:0.3.0
MCP_PERMISSION_MODE=trusted
MCP_TELEMETRY=off
MCP_AUTH_TOKEN=test-token
TUNNEL_PROVIDER=none
ENV
chmod 600 "$HOME_DIR/instances/legacy/instance.env"
(
  cd "$TMP"
  MCPCTL_HOME="$HOME_DIR" "$ROOT/bin/mcpctl" start legacy
)
[[ ! -e "$TMP/PWNED" ]]

mkdir -p "$HOME_DIR/instances/bad-provider"
cat > "$HOME_DIR/instances/bad-provider/instance.env" <<'ENV'
INSTANCE_NAME=bad-provider
MCP_PORT=19993
MCP_AUTH_TOKEN=test-token
TUNNEL_PROVIDER=$(touch PWNED_TUNNEL)
ENV
chmod 600 "$HOME_DIR/instances/bad-provider/instance.env"
(
  cd "$TMP"
  if MCPCTL_HOME="$HOME_DIR" "$ROOT/tunnel/run.sh" doctor bad-provider; then
    echo "malicious provider was unexpectedly accepted" >&2
    exit 1
  fi
)
[[ ! -e "$TMP/PWNED_TUNNEL" ]]

echo "instance env safety tests passed"
