# Home-Cluster

Local-state OpenTofu proof of concept for **one Home Assistant OS VM**, ID **130** (proposed, must be free), on Proxmox node `pve`, API `https://192.168.1.40:8006`. The existing ProxUI VM **102** at `10.30.0.20` is outside this project's state and permissions.

The VM uses the official HAOS **18.4** KVM QCOW2, OVMF/UEFI with Secure Boot keys disabled, 2 vCPU, 4096 MiB fixed RAM, a 32 GiB minimum disk and EFI disk on **local**, and one VirtIO NIC on existing **vmbr1**. Its prepared boot partition supplies static **10.30.0.30/24**, gateway **10.30.0.1**, DNS **1.1.1.1**. There is no DHCP dependency and no cloud-init disk. The intended IP is not yet verified as free.

No bridge, upstream Wi-Fi, host NAT, firewall, datastore, identity, or existing VM is managed here. No n8n or LLM workload is included. Image upload and API identity creation are separate administrator steps, requiring review. `apply.sh` deliberately refuses to run; the one reviewed apply (2026-11-16) ran `tofu apply` on a saved plan directly. Nothing has been pushed.

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
# Copy scripts/pve-preflight.sh to pve and run it as root in the web UI shell (see setup guide).
scripts/discover.sh   # prompts for the PREFLIGHT-OK line
scripts/plan.sh       # prompts again, for the run that covered the staged image
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
- `tofu plan -input=false` was attempted and stopped at missing `image_file_id`. `scripts/plan.sh` also correctly stopped at missing dedicated API credentials. A further non-applying plan with a synthetic SHA256 image ID reached provider configuration and failed with the explicit missing-credentials error.
- Image staged by the administrator at `local:import/haos-18.4-static-d4a0…15e5.qcow2`; image-bound `pve-preflight.sh` passed (checksum, `qemu-img check`, inventory, ARP). `scripts/plan.sh` then produced `artifacts/home-assistant.tfplan`: **1 to add, 0 to change, 0 to destroy**, VM 130 only, no reference to VM 102. Re-planned with Proxmox `protection = true`; same result.
- First apply failed before creating anything: the provider ignores `SSL_CERT_FILE` and uses the macOS keychain (`x509: “pve” certificate is not trusted`). After trusting the CA in the login keychain for SSL to `192.168.1.40` only, a fresh preflight and re-plan (same 1 create) were applied: **VM 130 created and running**. Proxmox config matches (OVMF, q35, 2 cores, 4096 MiB, `protection=1`, `onboot=1`, MAC `BC:24:11:30:00:30` on `vmbr1`, 32 GiB `scsi0` and EFI disk on `local`). State snapshot taken with `backup-state.sh`.
- From pve, `10.30.0.30` answered ARP from `bc:24:11:30:00:30` ~40 s after boot (boot-partition static profile imported; no DHCP) and `http://10.30.0.30:8123/` returned 302. Console `ha network info`, onboarding and a first HA backup are still to do.
- `prepare-image.sh` completed after installing qemu, mtools, xz and jq: prepared SHA256 `d4a0268217f710c3287585d039820145bcc5d6d11f010df057694ecd2e7515e5`, verified against `prepared.sha256`. It has not been staged; boot/static-IP behavior is untested.
- Root web-shell discovery on pve: `local` is `dir` with `images` and `import` (path `/var/lib/vz`, ~857 GB free); VMID 130 and MAC `BC:24:11:30:00:30` unused; `vmbr1` is `10.30.0.1/24`; `iputils-arping` installed by the administrator, and `arping -D` for `10.30.0.30` got 0 replies. Stopped VM 100 is on `vmbr1` with no Proxmox-side IP, so any in-disk static address is unverified. No `opentofu@pve` user, HAOS roles or token existed.
- Root SSH from the Mac is refused, and remains unconfigured by design. Privileged checks moved to `scripts/pve-preflight.sh` (web shell) with a pasted, image-bound, one-hour `PREFLIGHT-OK` attestation. `confirm_preflight` accept/reject cases were exercised locally. The script (SHA256 `f8da8322…40d5`) ran as root on pve with no image argument and passed.
- Administrator created `opentofu@pve`, roles `HAOSVM`/`HAOSStorage`/`HAOSNodeAudit`/`HAOSBridge` and privilege-separated token `home-assistant`; effective token permissions are only `/vms/130`, `/storage/local`, `/nodes/pve` and `/sdn/zones/localnetwork/vmbr1`. No DHCP server listens on the host.
- PVE root CA copied to ignored `pve-root-ca.pem` (SHA256 fingerprint `20:F3:03:47:…:24:B2:42` matches the host); the API certificate SAN includes `192.168.1.40`. Authenticated API calls pass with TLS verification. `GET /storage/local` returned 403 (it needs `Datastore.Allocate`), so `discover.sh` now reads `nodes/pve/storage?storage=local`; its API checks pass.
- A placeholder `SSL_CERT_FILE` in `.env` broke `tofu init` against the registry; `check.sh` now unsets it for init. ShellCheck reports only a false-positive SC2034 for `INFRA` in `common.sh`.
- Read-only SSH reached `pve`, reported PVE 9.2.26 and confirmed active `vmbr1` at `10.30.0.1/24`. The configured SSH user `tobin` cannot read `/etc/pve/storage.cfg`; `sudo` is absent.

The provider and lock file have been tested locally for validation only. VM 130 is deployed and reachable from pve; onboarding and backups remain. Network/Unix-socket restrictions in the Codex sandbox required approval for provider installation and the complete validation check.
