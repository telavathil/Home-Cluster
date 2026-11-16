#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
credentials
api nodes/pve/qemu/130/status/current | jq '.data | {vmid,name,status,uptime,maxmem}'
ssh -o BatchMode=yes -o ConnectTimeout=5 "${PVE_SSH_HOST:-pve}" 'curl --fail --silent --show-error --connect-timeout 5 --max-time 10 -o /dev/null -w "HA HTTP: %{http_code}\n" http://10.30.0.30:8123/'
