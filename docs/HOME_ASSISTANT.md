# Home Assistant (VM 130)

The only cluster workload managed by this repository's OpenTofu configuration (`infra/home-assistant/`, local state on the Mac). Deployed 2026-11-16 and running.

| Setting | Value |
|---|---|
| Image | Official HAOS **18.4** KVM QCOW2, with a static network profile added to its boot partition (`scripts/prepare-image.sh`) |
| Firmware / machine | OVMF/UEFI, Secure Boot keys not enrolled, q35 |
| CPU / RAM | 2 cores (`host`), 4096 MiB fixed |
| Disks | 32 GiB `scsi0` qcow2 and EFI disk on `local` |
| Network | One VirtIO NIC on `vmbr1`, MAC `BC:24:11:30:00:30` |
| Address | Static **10.30.0.30/24**, gateway **10.30.0.1**, DNS **1.1.1.1**. No DHCP, no cloud-init |
| Guards | OpenTofu `prevent_destroy` plus Proxmox `protection=1`; starts on host boot |
| API identity | `opentofu@pve!home-assistant`, scoped to `/vms/130`, `/storage/local`, `/nodes/pve` and `vmbr1` only |

Image staging and identity creation are separate, reviewed administrator steps. `scripts/apply.sh` deliberately refuses to run; the one reviewed apply ran `tofu apply` on a saved plan directly. See [setup](HOME_ASSISTANT_SETUP.md) for the full procedure and [recovery](RECOVERY.md) for state and HA backups.

## Workflow

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
# Copy scripts/pve-preflight.sh to pve and run it as root in the web UI shell (see setup).
scripts/discover.sh   # prompts for the PREFLIGHT-OK line
scripts/plan.sh       # prompts again, for the run that covered the staged image
# STOP and review. Apply only with explicit authorization.
```

`scripts/status.sh` reports VM status through the API and probes the UI from pve. The preflight refuses once VM 130 exists, so later changes use direct, reviewed `tofu plan` runs.

## Access

The deployed Home Assistant serves its UI on guest port **80**. Port 8123 answers only with a `307` to port 80 on the requested host, which through a tunnel becomes `http://localhost/` on the Mac and fails, so tunnels forward to port 80. HAOS has no SSH login, so the tunnel ends at pve.

```sh
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8123:10.30.0.30:80 pve
```

Open [http://localhost:8123](http://localhost:8123). Binding explicitly to loopback limits exposure.

For an always-on tunnel, the Mac uses a `home-assistant-ui` host in `~/.ssh/config` (`HostName 192.168.1.40`, `User tobin`, `LocalForward 127.0.0.1:8123 10.30.0.30:80`, `ExitOnForwardFailure yes`, `ServerAliveInterval 30`) and the LaunchAgent `~/Library/LaunchAgents/com.homecluster.home-assistant-tunnel.plist`. It runs `/usr/bin/ssh -N -T -o BatchMode=yes -o ConnectTimeout=10 home-assistant-ui` with `RunAtLoad`, `KeepAlive` and a 30 s throttle, logging to `~/Library/Logs/home-assistant-tunnel.log`. Both live outside the repository and mirror the ProxUI tunnel.

```sh
launchctl kickstart -k gui/$(id -u)/com.homecluster.home-assistant-tunnel   # restart
launchctl bootout gui/$(id -u)/com.homecluster.home-assistant-tunnel        # stop
```

## Validation record (2026-11-16)

In order of events:

- OpenTofu 1.13.9 on macOS arm64; bpg/proxmox **0.112.0** installed from its signed release and pinned in the lock file.
- `scripts/check.sh`: `tofu fmt -check`, initialization with the lock file, `tofu validate`, and Bash syntax checks passed with the required sandbox permissions. This tests configuration/schema compatibility, not a live deployment.
- `tofu plan -input=false` was attempted and stopped at missing `image_file_id`. `scripts/plan.sh` also correctly stopped at missing dedicated API credentials. A further non-applying plan with a synthetic SHA256 image ID reached provider configuration and failed with the explicit missing-credentials error.
- Read-only SSH reached `pve`, reported PVE 9.2.26 and confirmed active `vmbr1` at `10.30.0.1/24`. The configured SSH user `tobin` cannot read `/etc/pve/storage.cfg`; `sudo` is absent.
- `prepare-image.sh` completed after installing qemu, mtools, xz and jq: prepared SHA256 `d4a0268217f710c3287585d039820145bcc5d6d11f010df057694ecd2e7515e5`, verified against `prepared.sha256`.
- Root web-shell discovery on pve: `local` is `dir` with `images` and `import` (path `/var/lib/vz`, ~857 GB free); VMID 130 and MAC `BC:24:11:30:00:30` unused; `vmbr1` is `10.30.0.1/24`; `iputils-arping` installed by the administrator, and `arping -D` for `10.30.0.30` got 0 replies. Stopped VM 100 is on `vmbr1` with no Proxmox-side IP, so any in-disk static address is unverified. No `opentofu@pve` user, HAOS roles or token existed.
- A placeholder `SSL_CERT_FILE` in `.env` broke `tofu init` against the registry; `check.sh` now unsets it for init. ShellCheck reports only a false-positive SC2034 for `INFRA` in `common.sh`.
- Root SSH from the Mac is refused, and remains unconfigured by design. Privileged checks moved to `scripts/pve-preflight.sh` (web shell) with a pasted, image-bound, one-hour `PREFLIGHT-OK` attestation. `confirm_preflight` accept/reject cases were exercised locally. The script (SHA256 `f8da8322…40d5`) ran as root on pve with no image argument and passed.
- Administrator created `opentofu@pve`, roles `HAOSVM`/`HAOSStorage`/`HAOSNodeAudit`/`HAOSBridge` and privilege-separated token `home-assistant`; effective token permissions are only `/vms/130`, `/storage/local`, `/nodes/pve` and `/sdn/zones/localnetwork/vmbr1`. No DHCP server listens on the host.
- PVE root CA copied to ignored `pve-root-ca.pem` (SHA256 fingerprint `20:F3:03:47:…:24:B2:42` matches the host); the API certificate SAN includes `192.168.1.40`. Authenticated API calls pass with TLS verification. `GET /storage/local` returned 403 (it needs `Datastore.Allocate`), so `discover.sh` now reads `nodes/pve/storage?storage=local`; its API checks pass.
- Image staged by the administrator at `local:import/haos-18.4-static-d4a0…15e5.qcow2`; image-bound `pve-preflight.sh` passed (checksum, `qemu-img check`, inventory, ARP). `scripts/plan.sh` then produced `artifacts/home-assistant.tfplan`: **1 to add, 0 to change, 0 to destroy**, VM 130 only, no reference to VM 102. Re-planned with Proxmox `protection = true`; same result.
- First apply failed before creating anything: the provider ignores `SSL_CERT_FILE` and uses the macOS keychain (`x509: “pve” certificate is not trusted`). After trusting the CA in the login keychain for SSL to `192.168.1.40` only, a fresh preflight and re-plan (same 1 create) were applied: **VM 130 created and running**. Proxmox config matches (OVMF, q35, 2 cores, 4096 MiB, `protection=1`, `onboot=1`, MAC `BC:24:11:30:00:30` on `vmbr1`, 32 GiB `scsi0` and EFI disk on `local`). State snapshot taken with `backup-state.sh`.
- From pve, `10.30.0.30` answered ARP from `bc:24:11:30:00:30` ~40 s after boot (boot-partition static profile imported; no DHCP) and `http://10.30.0.30:8123/` returned 302 while the landing page ran. Once Core started, port 8123 returned `307` to port 80, and `http://10.30.0.30/` served onboarding; the tunnel was switched to port 80 and `http://localhost:8123/onboarding.html` returned 200.
- The stored `ssh_tunnel` output in local state still shows the pre-fix port 8123 value; it updates on the next reviewed apply, which should show no infrastructure change.

Still to do: console `ha network info`, onboarding and a first HA backup copied off the VM. Network/Unix-socket restrictions in the Codex sandbox required approval for provider installation and the complete validation check.
