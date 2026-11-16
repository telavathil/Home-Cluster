#!/usr/bin/env bash
# Shared setup; .env is trusted local shell code. Never run with shell tracing.
set -euo pipefail
umask 077
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INFRA="$ROOT/infra/home-assistant"
if [[ -f "$ROOT/.env" ]]; then
  set -a
  source "$ROOT/.env"
  set +a
fi
export TF_IN_AUTOMATION=1
unset TF_CLI_ARGS TF_CLI_ARGS_apply TF_CLI_ARGS_plan
fail() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || fail "Missing tool: $1"; }
credentials() {
  [[ ${PROXMOX_VE_API_TOKEN:-} == opentofu@pve\!home-assistant=* ]] || fail 'Set the dedicated PROXMOX_VE_API_TOKEN in .env (see docs/CLUSTER_SETUP.md).'
  [[ $PROXMOX_VE_API_TOKEN != *REPLACE* ]] || fail 'Replace the example API token.'
}
api() {
  local tls=()
  [[ ${TF_VAR_insecure:-false} != true ]] || tls=(-k)
  # Header on stdin avoids exposing the token in process arguments.
  printf 'header = "Authorization: PVEAPIToken=%s"\n' "$PROXMOX_VE_API_TOKEN" |
    curl -q --config - --fail --silent --show-error --connect-timeout 5 --max-time 30 "${tls[@]}" "https://192.168.1.40:8006/api2/json/$1"
}
