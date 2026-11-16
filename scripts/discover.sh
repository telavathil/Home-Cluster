#!/usr/bin/env bash
# API checks from the Mac, then the operator confirms pve-preflight.sh ran as root on pve.
# Usage: discover.sh [IMAGE_FILE_ID]  (initial discovery before staging takes no argument)
source "$(dirname "$0")/common.sh"
[[ $# -le 1 ]] || fail 'Usage: discover.sh [IMAGE_FILE_ID]'
credentials
need jq
# The node view needs only Datastore.Audit; /storage/local would need Datastore.Allocate.
storage=$(api 'nodes/pve/storage?storage=local')
jq -e '.data | length == 1 and (.[0] | (.type == "dir") and ((.content | split(",") | index("images")) != null) and ((.content | split(",") | index("import")) != null))' <<<"$storage" >/dev/null || fail 'local must be directory storage with images AND import enabled. No storage changes were made.'
jq -e '.data[0] | .active == 1 and .enabled == 1 and .avail >= 42949672960' <<<"$storage" >/dev/null || fail 'local unavailable or has less than 40 GiB free.'
api nodes/pve/network | jq -e '.data[] | select(.iface == "vmbr1" and .active == 1)' >/dev/null || fail 'vmbr1 is not active.'
confirm_preflight "${1:-}"
echo 'Preflight confirmed for initial creation.'
