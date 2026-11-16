#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
credentials
need jq
storage=$(api storage/local)
jq -e '.data | (.type == "dir") and ((.content | split(",") | index("images")) != null) and ((.content | split(",") | index("import")) != null)' <<<"$storage" >/dev/null || fail 'local must be directory storage with images AND import enabled. No storage changes were made.'
api nodes/pve/storage/local/status | jq -e '.data | .active == 1 and .enabled == 1 and .avail >= 42949672960' >/dev/null || fail 'local unavailable or has less than 40 GiB free.'
api nodes/pve/network | jq -e '.data[] | select(.iface == "vmbr1" and .active == 1)' >/dev/null || fail 'vmbr1 is not active.'
# Restricted token cannot prove absence of guests outside its ACL. Use administrator read-only inventory.
ssh -o BatchMode=yes -o ConnectTimeout=5 "${PVE_ADMIN_SSH_HOST:-root@192.168.1.40}" 'bash -s' <<'REMOTE'
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
command -v arping >/dev/null || { echo 'arping missing: administrator must review installing iputils-arping.' >&2; exit 1; }
[[ $(id -u) == 0 ]] || { echo 'Discovery needs an administrator read-only SSH session.' >&2; exit 1; }
inventory=$(pvesh get /cluster/resources --type vm --output-format json)
command -v python3 >/dev/null || { echo 'python3 is required for full inventory checks.' >&2; exit 1; }
printf '%s\n' "$inventory" | python3 -c 'import json,sys; v=json.load(sys.stdin); print(json.dumps(v,indent=2)); sys.exit(1 if any(x.get("vmid")==130 for x in v) else 0)'
if [[ -e /etc/pve/qemu-server/130.conf || -e /etc/pve/lxc/130.conf ]]; then
  echo 'VMID 130 exists: inspect state and inventory; do not create over it.' >&2
  exit 1
fi
# ARP duplicate-address detection on the actual L2 segment, not a Mac ping.
arping -D -I vmbr1 -c 3 -w 5 10.30.0.30
REMOTE
echo 'Preflight passed for initial creation. Also reconcile powered-off guest configs and your address inventory; ARP silence alone is not proof of availability.'
