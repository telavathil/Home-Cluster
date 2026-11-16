#!/usr/bin/env bash
# Local files only. Does not SSH, upload files, or modify Proxmox.
source "$(dirname "$0")/common.sh"
[[ $# == 0 ]] || fail 'Usage: prepare-image.sh (no arguments)'
for tool in curl xz qemu-img python3 mcopy mmd mdir shasum; do need "$tool"; done
mkdir -p "$ROOT/artifacts"
work=$(mktemp -d "$ROOT/artifacts/prepare.XXXXXX")
echo "Working directory: $work (retained for inspection; contains no credentials)"
archive="$ROOT/artifacts/haos_ova-18.4.qcow2.xz"
expected=756ec485b1b153099ca53e88a5eebd63a801d56b791afe5c6d63ef94a35dc02d
if [[ ! -f "$archive" ]]; then
  curl -q --fail --location --retry 3 --proto '=https' --proto-redir '=https' \
    https://github.com/home-assistant/operating-system/releases/download/18.4/haos_ova-18.4.qcow2.xz \
    -o "$work/download.xz"
  [[ $(shasum -a 256 "$work/download.xz" | cut -d ' ' -f1) == "$expected" ]] || fail 'Official compressed image checksum mismatch.'
  mv "$work/download.xz" "$archive"
fi
[[ $(shasum -a 256 "$archive" | cut -d ' ' -f1) == "$expected" ]] || fail 'Cached image checksum mismatch; inspect it manually.'
xz -t "$archive"
xz -dc "$archive" > "$work/original.qcow2"
qemu-img check -f qcow2 "$work/original.qcow2"
qemu-img convert -f qcow2 -O raw "$work/original.qcow2" "$work/disk.raw"
# Locate the named GPT boot partition; never mount a host disk or guess offsets.
offset=$(python3 - "$work/disk.raw" <<'PY'
import struct, sys
with open(sys.argv[1], 'rb') as f:
    f.seek(512)
    h = f.read(512)
    assert h[:8] == b'EFI PART', 'Expected GPT with 512-byte sectors'
    lba, count, size = struct.unpack_from('<QII', h, 72)
    assert 0 < count <= 1024 and 128 <= size <= 4096
    found = []
    for i in range(count):
        f.seek(lba * 512 + i * size)
        e = f.read(size)
        name = e[56:128].decode('utf-16le').rstrip('\0')
        if name == 'hassos-boot':
            found.append(struct.unpack_from('<Q', e, 32)[0] * 512)
    assert len(found) == 1, 'Expected exactly one hassos-boot partition'
    print(found[0])
PY
)
cat > "$work/home-assistant.nmconnection" <<'PROFILE'
[connection]
id=home-assistant-static
uuid=706f6bb2-d9e8-4ace-8992-303030303030
type=ethernet
autoconnect=true

[ethernet]
mac-address=BC:24:11:30:00:30

[ipv4]
method=manual
address1=10.30.0.30/24,10.30.0.1
dns=1.1.1.1;
ignore-auto-dns=true

[ipv6]
method=disabled
PROFILE
fat="$work/disk.raw@@$offset"
mdir -i "$fat" ::
mmd -i "$fat" ::/CONFIG
mmd -i "$fat" ::/CONFIG/network
mcopy -i "$fat" "$work/home-assistant.nmconnection" ::/CONFIG/network/home-assistant.nmconnection
mcopy -i "$fat" ::/CONFIG/network/home-assistant.nmconnection "$work/readback"
cmp "$work/home-assistant.nmconnection" "$work/readback"
qemu-img convert -f raw -O qcow2 "$work/disk.raw" "$work/prepared.qcow2"
qemu-img check -f qcow2 "$work/prepared.qcow2"
digest=$(shasum -a 256 "$work/prepared.qcow2" | cut -d ' ' -f1)
name="haos-18.4-static-$digest.qcow2"
if [[ -f "$ROOT/artifacts/$name" ]]; then
  [[ $(shasum -a 256 "$ROOT/artifacts/$name" | cut -d ' ' -f1) == "$digest" ]] || fail 'Existing prepared image is corrupt.'
else
  mv "$work/prepared.qcow2" "$ROOT/artifacts/$name"
fi
printf '%s  %s\n' "$digest" "$name" > "$ROOT/artifacts/prepared.sha256"
printf '%s\n' "Official source SHA256: $expected" "Prepared SHA256: $digest" \
  'IP: 10.30.0.30/24; gateway: 10.30.0.1; DNS: 1.1.1.1; MAC: BC:24:11:30:00:30' \
  "qemu-img: $(qemu-img --version | head -1)" > "$ROOT/artifacts/image-manifest.txt"
printf '\nLocal preparation complete. Review before staging on pve.\nimage_file_id = "local:import/%s"\n' "$name"
