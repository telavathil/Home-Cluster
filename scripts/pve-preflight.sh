#!/usr/bin/env bash
# Runs ON pve as root (web UI Shell); there is no administrator SSH from the Mac.
# Read-only: inspects guest inventory, ARP on vmbr1 and, optionally, a staged image.
# Usage: pve-preflight.sh [local:import/haos-18.4-static-SHA256.qcow2]
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
VMID=130
IP=10.30.0.30
MAC=BC:24:11:30:00:30
BRIDGE=vmbr1
fail() { echo "PREFLIGHT FAILED: $*" >&2; exit 1; }
[[ $# -le 1 ]] || fail 'Usage: pve-preflight.sh [IMAGE_FILE_ID]'
[[ $(id -u) == 0 ]] || fail 'Run as root in the Proxmox web UI shell.'
for tool in pvesh pvesm python3 arping qemu-img sha256sum; do
  command -v "$tool" >/dev/null || fail "Missing tool: $tool"
done

# Full inventory as root; the restricted token's ACL-filtered view cannot prove absence.
pvesh get /cluster/resources --type vm --output-format json |
  python3 -c 'import json,sys; v=json.load(sys.stdin); [print(g.get("vmid"), g.get("type"), g.get("name"), g.get("status")) for g in v]; sys.exit(1 if any(g.get("vmid")==int(sys.argv[1]) for g in v) else 0)' "$VMID" ||
  fail "VMID $VMID exists: inspect state and inventory; do not create over it."
if compgen -G "/etc/pve/nodes/*/qemu-server/$VMID.conf" >/dev/null || compgen -G "/etc/pve/nodes/*/lxc/$VMID.conf" >/dev/null; then
  fail "A config for VMID $VMID exists."
fi
if grep -rqi "$MAC" /etc/pve/nodes/*/qemu-server/ /etc/pve/nodes/*/lxc/ 2>/dev/null; then
  fail "MAC $MAC is already used by a guest config."
fi

# ARP duplicate-address detection on the actual L2 segment; exit 0 means no replies.
arping -D -I "$BRIDGE" -c 3 -w 5 "$IP" || fail "$IP answered ARP or the probe was inconclusive."

image=none
if [[ $# == 1 ]]; then
  [[ $1 =~ ^local:import/haos-18\.4-static-([0-9a-f]{64})\.qcow2$ ]] || fail 'Invalid prepared image ID.'
  expected=${BASH_REMATCH[1]}
  path=$(pvesm path "$1")
  [[ -f $path ]] || fail "Staged image not found at $path."
  [[ $(sha256sum "$path" | cut -d ' ' -f1) == "$expected" ]] || fail 'Staged image checksum does not match its filename.'
  qemu-img check -f qcow2 "$path" >/dev/null || fail 'Staged image failed qemu-img check.'
  image=$1
fi

echo 'Preflight passed. Also reconcile powered-off guests (static IPs inside disks) and your address inventory; ARP silence alone is not proof.'
echo "PREFLIGHT-OK vmid=$VMID ip=$IP image=$image time=$(date -u +%s)"
