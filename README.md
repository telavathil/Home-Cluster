# Home-Cluster

Local-state OpenTofu proof of concept for **one Home Assistant OS VM**, ID **130** (proposed, must be free), on Proxmox node `pve`, API `https://192.168.1.40:8006`. The existing ProxUI VM **102** at `10.30.0.20` is outside this project's state and permissions.

The VM uses the official HAOS **18.4** KVM QCOW2, OVMF/UEFI with Secure Boot keys disabled, 2 vCPU, 4096 MiB fixed RAM, a 32 GiB minimum disk and EFI disk on **local**, and one VirtIO NIC on existing **vmbr1**. Its prepared boot partition supplies static **10.30.0.30/24**, gateway **10.30.0.1**, DNS **1.1.1.1**. There is no DHCP dependency and no cloud-init disk. The intended IP is not yet verified as free.

No bridge, upstream Wi-Fi, host NAT, firewall, datastore, identity, or existing VM is managed here. No n8n or LLM workload is included. Image upload and API identity creation are separate administrator steps, requiring review. `apply.sh` deliberately refuses to run in this initial scaffold. Nothing has been applied or pushed.

## Start here

Read [cluster setup](docs/CLUSTER_SETUP.md) before executing administrator commands. See [recovery](docs/RECOVERY.md) for local state and HA backups.

```sh
cp .env.example .env
chmod 600 .env
# Populate the dedicated token and trusted CA path; do not paste secrets into tfvars.
scripts/check.sh
# Install missing image tools after review: brew install qemu mtools xz jq
scripts/prepare-image.sh
# Review and stage the prepared image using the documented administrator procedure.
cp infra/home-assistant/terraform.tfvars.example infra/home-assistant/terraform.tfvars
# Set image_file_id to the value printed by prepare-image.sh.
scripts/discover.sh
scripts/plan.sh
# STOP and review. No apply is authorized.
```

Access after a separately reviewed deployment:

```sh
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8123:10.30.0.30:8123 pve
```

Open [http://localhost:8123](http://localhost:8123). The basic equivalent is `ssh -L 8123:10.30.0.30:8123 pve`; binding explicitly to loopback limits exposure. The Mac does not need a route to the Services subnet.

## Validation record (2026-11-16)

- OpenTofu 1.13.9 on macOS arm64; bpg/proxmox **0.112.0** installed from its signed release and pinned in the lock file.
- `scripts/check.sh`: `tofu fmt -check`, initialization with the lock file, `tofu validate`, and Bash syntax checks passed with the required sandbox permissions. This tests configuration/schema compatibility, not a live deployment.
- `tofu plan -input=false` was attempted and stopped at missing `image_file_id`. `scripts/plan.sh` also correctly stopped at missing dedicated API credentials. A further non-applying plan with a synthetic SHA256 image ID reached provider configuration and failed with the explicit missing-credentials error. No usable deployment plan exists yet.
- `prepare-image.sh` stopped before downloading or modifying an image: `mcopy` is missing. Image boot/static-IP behavior has not been tested on this host.
- Read-only SSH reached `pve`, reported PVE 9.2.26 and confirmed active `vmbr1` at `10.30.0.1/24`. The configured SSH user `tobin` cannot read `/etc/pve/storage.cfg`; `sudo` is absent. Storage content types, free capacity, VM inventory, VMID 130 and IP availability remain blockers.

The provider and lock file have been tested locally for validation only. A successful authenticated plan and VM boot are still required. Network/Unix-socket restrictions in the Codex sandbox required approval for provider installation and the complete validation check.
