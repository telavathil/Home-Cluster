#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
credentials
[[ -f "$INFRA/terraform.tfvars" ]] || fail 'Create terraform.tfvars from the example after image preparation.'
"$ROOT/scripts/check.sh"
"$ROOT/scripts/discover.sh"
# Resolve the exact HCL variable through OpenTofu, rather than parsing tfvars text.
file_id=$(printf 'var.image_file_id\n' | tofu -chdir="$INFRA" console | jq -r .)
[[ $file_id =~ ^local:import/haos-18\.4-static-([0-9a-f]{64})\.qcow2$ ]] || fail 'Invalid prepared image ID.'
expected=${BASH_REMATCH[1]}
api nodes/pve/storage/local/content | jq -e --arg id "$file_id" '.data[] | select(.volid == $id)' >/dev/null || fail 'Prepared image is not staged in local:import.'
# file_id has been restricted to safe literal characters above.
actual=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "${PVE_ADMIN_SSH_HOST:-root@192.168.1.40}" "sha256sum \"\$(/usr/sbin/pvesm path '$file_id')\"" | cut -d ' ' -f1)
[[ $actual == "$expected" ]] || fail 'Staged image checksum does not match its filename.'
mkdir -p "$ROOT/artifacts"
tofu -chdir="$INFRA" plan -input=false -out="$ROOT/artifacts/home-assistant.tfplan"
tofu -chdir="$INFRA" show -no-color "$ROOT/artifacts/home-assistant.tfplan"
echo 'STOP: review the plan, image staging and inventory before requesting apply.'
