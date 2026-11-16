# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Documentation and infrastructure-as-code for the single-node Proxmox home cluster (`pve`, its networks `vmbr1`/`vmbr2` and guests 100, 101, 102, 130, 9000). `README.md` is the cluster overview: host, networks, guest inventory and Mac access. Only one workload is under OpenTofu: local-state config in `infra/home-assistant/` defining exactly **one Home Assistant OS 18.4 VM (VMID 130)** on Proxmox node `pve` (API `https://192.168.1.40:8006`), static IP `10.30.0.30/24` on existing bridge `vmbr1`. It is deliberately review-gated: VM 130 was applied once, on 2026-11-16, from a reviewed saved plan by running `tofu apply` directly; `scripts/apply.sh` still always fails by design. Do not make it apply, and do not run host-mutating commands (image upload, `pveum`, `pvesm set`, `apt-get`, `tofu apply`, `tofu import`, VM power/config changes) without explicit authorization in the current session.

Not managed by OpenTofu and never to be imported: VM 102 (ProxUI, `10.30.0.20`), `proxui@pve`, bridges, Wi-Fi, NAT, firewall, storage config, identities. The host firewall/NAT (`/etc/nftables/homelab.nft`, loaded by `homelab-nftables.service`) is documented in the README and changed only manually with explicit approval. The service deletes both `homelab` tables before loading, so always run `nft -c -f` before restarting it. It carries one port forward: Wi-Fi `:8123` → `10.30.0.30:80` for LAN access to Home Assistant.

## Commands

All scripts run from the repo root and source `scripts/common.sh` (strict mode, `umask 077`, loads `.env` as shell code, defines `fail`/`need`/`credentials`/`api`).

| Command | Purpose | Touches Proxmox? |
|---|---|---|
| `scripts/check.sh` | `tofu fmt -check`, `init -lockfile=readonly`, `validate`, `bash -n` on all scripts. The "test suite". | No |
| `scripts/prepare-image.sh` | Download pinned HAOS qcow2.xz, verify SHA256, inject static NetworkManager profile into the `hassos-boot` FAT partition via mtools, emit content-addressed `artifacts/haos-18.4-static-<sha>.qcow2` and the `image_file_id`. Needs `brew install qemu mtools xz jq`. | No |
| `scripts/pve-preflight.sh` | **Runs on pve as root in the web UI shell**, not on the Mac. Full VMID inventory (fails if 130 exists), MAC in guest configs, `arping -D` for the IP, and with an image ID arg the staged file's SHA256 + `qemu-img check`. Prints a `PREFLIGHT-OK … time=<epoch>` line. | Read-only |
| `scripts/discover.sh [IMAGE_ID]` | API checks (`local` storage type/content/free space, `vmbr1` active), then prompts for the pasted `PREFLIGHT-OK` line. | Read-only |
| `scripts/plan.sh` | `check` + staged image exists via API + `discover` with the image ID, then `tofu plan -out=artifacts/home-assistant.tfplan`. Interactive. | Read-only |
| `scripts/status.sh` | VM 130 status via API + HA HTTP probe from `pve`. | Read-only |
| `scripts/backup-state.sh` | `tofu state pull` snapshot + sha256 into `backups/`. | No |

Run OpenTofu directly with `tofu -chdir=infra/home-assistant <cmd>`. Version constraints: OpenTofu `>= 1.13.0, < 1.14.0`, provider `bpg/proxmox = 0.112.0` (lock file is committed; init with `-lockfile=readonly`).

## Architecture / non-obvious design decisions

- **Static IP via boot partition, not cloud-init.** HAOS does not consume cloud-init, so there is no `initialization` block. `prepare-image.sh` writes `CONFIG/network/home-assistant.nmconnection` (bound to MAC `BC:24:11:30:00:30`) which HAOS imports on first boot. The MAC, IP, gateway (`10.30.0.1`), DNS (`1.1.1.1`) are duplicated across `prepare-image.sh`, `main.tf`, `pve-preflight.sh`, `confirm_preflight` in `common.sh`, `status.sh`, `outputs.tf` and docs — change them everywhere together. Never switch to DHCP.
- **Image pipeline is content-addressed.** `image_file_id` must match `^local:import/haos-18\.4-static-[0-9a-f]{64}\.qcow2$` (enforced in both `variables.tf` validation and `plan.sh`). The source is staged manually by an administrator into `local:import`; OpenTofu uses `disk.import_from` through the API, so the provider needs no SSH config. The HAOS version (18.4) is pinned in several places; upgrades require separate review (18.5 has no KVM image).
- **Least-privilege auth.** Credentials come only from `PROXMOX_VE_API_TOKEN` in `.env` (must be `opentofu@pve!home-assistant=...`; `credentials()` enforces this). `api()` passes the token header via curl stdin to keep it out of process args. Never put secrets in tfvars or CLI args. TLS verification defaults on (`SSL_CERT_FILE`); `TF_VAR_insecure=true` is an explicit opt-out affecting both provider and `api()`.
- **No administrator SSH.** The only SSH from the Mac is `PVE_SSH_HOST` (`pve`, unprivileged user `tobin`, no sudo) for status, tunnel and `scp` uploads. Root SSH is deliberately not enabled. Privileged checks (needed because the restricted token's ACL-filtered view cannot prove VMID 130 is free) run via `pve-preflight.sh` in the web shell, and the operator pastes the result line into `confirm_preflight` (`common.sh`), which rejects a different image or a result older than 1 hour. It is an attestation, not proof. It reads the line from stdin, so `discover.sh`/`plan.sh` are interactive unless it is piped in.
- **TLS trust is split.** `SSL_CERT_FILE` (only the PVE CA) is honoured by `curl`/`api()` and by `tofu` itself, so `check.sh` unsets it for `tofu init` (registry access). The provider binary ignores it and uses the macOS keychain, where the CA is trusted only for SSL to `192.168.1.40` (see `docs/HOME_ASSISTANT_SETUP.md`).
- **Safety guards.** `prevent_destroy = true` (OpenTofu) plus `protection = true` (Proxmox refuses deletion/disk removal until an administrator clears it), `stop_on_destroy = false`, QEMU agent disabled (avoids bootstrap waits). A valid initial plan must be exactly one create of VM 130. The preflight is initial-creation only — it refuses once VM 130 exists.
- **HA UI is on guest port 80**, not 8123: 8123 only returns a 307 to port 80 on the requested host, which breaks through a tunnel. Tunnels forward local `127.0.0.1:8123` → `10.30.0.30:80`; `status.sh` probes port 80. The always-on tunnel (`home-assistant-ui` in `~/.ssh/config` + LaunchAgent `com.homecluster.home-assistant-tunnel`) lives outside the repo.
- **State is local** at `infra/home-assistant/terraform.tfstate`. `artifacts/`, `backups/`, `.env`, `*.tfvars`, state, plans, and images are gitignored.

## Docs

`docs/HOME_ASSISTANT_SETUP.md` is the authoritative administrator procedure (discovery, API identity/ACLs, TLS trust, image staging, plan review, post-deploy verification). `docs/RECOVERY.md` covers state backup/restore, lost-state import, and failed-boot troubleshooting. `docs/HOME_ASSISTANT.md` is the workload page and holds the dated validation record of what has and hasn't been verified — update it when validation status changes. Update the README's host/network/guest tables when the cluster changes, and mark facts that were not verified. Keep the cautious, review-first tone: mark host mutations as such and do not present untested steps as verified.
