#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
credentials
[[ -f "$INFRA/terraform.tfvars" ]] || fail 'Create terraform.tfvars from the example after image preparation.'
"$ROOT/scripts/check.sh"
# Resolve the exact HCL variable through OpenTofu, rather than parsing tfvars text.
file_id=$(printf 'var.image_file_id\n' | tofu -chdir="$INFRA" console | jq -r .)
[[ $file_id =~ ^local:import/haos-18\.4-static-[0-9a-f]{64}\.qcow2$ ]] || fail 'Invalid prepared image ID.'
api nodes/pve/storage/local/content | jq -e --arg id "$file_id" '.data[] | select(.volid == $id)' >/dev/null || fail 'Prepared image is not staged in local:import.'
# Inventory, ARP and the staged image's checksum are verified by pve-preflight.sh on pve.
"$ROOT/scripts/discover.sh" "$file_id"
mkdir -p "$ROOT/artifacts"
tofu -chdir="$INFRA" plan -input=false -out="$ROOT/artifacts/home-assistant.tfplan"
tofu -chdir="$INFRA" show -no-color "$ROOT/artifacts/home-assistant.tfplan"
echo 'STOP: review the plan, image staging and inventory before requesting apply.'
