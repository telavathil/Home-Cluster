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
  [[ ${PROXMOX_VE_API_TOKEN:-} == opentofu@pve\!home-assistant=* ]] || fail 'Set the dedicated PROXMOX_VE_API_TOKEN in .env (see docs/HOME_ASSISTANT_SETUP.md).'
  [[ $PROXMOX_VE_API_TOKEN != *REPLACE* ]] || fail 'Replace the example API token.'
}
# Privileged host checks run in the pve web shell (no administrator SSH); the operator
# pastes the result line. This is an attestation, not proof: read the preflight output.
confirm_preflight() {
  local image=$1 line seen stamp now
  echo "As root in the pve web UI shell, run: bash /root/pve-preflight.sh${image:+ $image}" >&2
  read -r -p 'Paste the PREFLIGHT-OK line: ' line || fail 'No preflight result entered.'
  [[ $line =~ ^PREFLIGHT-OK\ vmid=130\ ip=10\.30\.0\.30\ image=([^ ]+)\ time=([0-9]+)$ ]] || fail 'Not a PREFLIGHT-OK line.'
  seen=${BASH_REMATCH[1]}
  stamp=${BASH_REMATCH[2]}
  [[ $seen == "${image:-none}" ]] || fail "Preflight covered image '$seen', expected '${image:-none}'."
  now=$(date -u +%s)
  (( stamp <= now + 300 && now - stamp <= 3600 )) || fail 'Preflight result is not from the last hour; rerun it.'
}
api() {
  local tls=()
  [[ ${TF_VAR_insecure:-false} != true ]] || tls=(-k)
  # Header on stdin avoids exposing the token in process arguments.
  printf 'header = "Authorization: PVEAPIToken=%s"\n' "$PROXMOX_VE_API_TOKEN" |
    curl -q --config - --fail --silent --show-error --connect-timeout 5 --max-time 30 "${tls[@]}" "https://192.168.1.40:8006/api2/json/$1"
}
