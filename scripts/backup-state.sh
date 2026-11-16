#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
[[ $# == 0 ]] || fail 'Usage: backup-state.sh (no arguments)'
[[ -f "$INFRA/terraform.tfstate" ]] || fail 'No local state exists yet.'
[[ ! -f "$INFRA/.terraform.tfstate.lock.info" ]] || fail 'State is locked; wait for OpenTofu to finish.'
need tofu
need jq
mkdir -p "$ROOT/backups"
backup=$(mktemp "$ROOT/backups/state-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
tofu -chdir="$INFRA" state pull > "$backup"
jq -e '.lineage and (.serial >= 0)' "$backup" >/dev/null
shasum -a 256 "$backup" > "$backup.sha256"
echo "State snapshot: $backup"
echo 'Also copy .terraform.lock.hcl, local tfvars, and image manifest to encrypted offline storage. Never run concurrently with apply.'
