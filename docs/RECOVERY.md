# Recovery

## What is backed up

OpenTofu state maps this configuration to VM 130. It is not a copy of HAOS disks or Home Assistant data. Keep three things separately: local state/configuration, the prepared image plus provenance/checksums, and Home Assistant backups (plus optional administrator-managed Proxmox VM backups). Use encrypted off-Mac storage; `.gitignore` prevents accidental Git inclusion, not disk loss. State and plans can contain sensitive information.

## Local state backup

Run only when no OpenTofu process is active, immediately after a successful approved apply and before subsequent changes:

```sh
scripts/backup-state.sh
```

The script uses `tofu state pull`, checks JSON lineage/serial, creates a unique mode-600 snapshot under ignored `backups/`, and writes a SHA256 sidecar. An active local lock causes refusal; the operator must also avoid starting another process during backup. No remote backend is configured. OpenTofu's own `terraform.tfstate.backup` is useful but not an independent backup.

Copy the snapshot, sidecar, `.terraform.lock.hcl`, Git revision/configuration, ignored `terraform.tfvars`, image manifest, prepared QCOW2 and source checksum to encrypted external storage. Store the API token separately in a password manager or encrypted environment-file backup. Never put these private artifacts into Git. Losing a token does not require recreating the VM: rotate that token with the administrator, then update `.env`.

## Restore state on the Mac

First stop all OpenTofu operations. Inspect any `.terraform.tfstate.lock.info` and confirm its process is gone; don't blindly delete locks or use `-lock=false`. Restore the same repository revision and provider lock file. Do not run apply against empty state if VM 130 may already exist.

```sh
# Substitute the actual backup paths. Verify before copying.
shasum -a 256 -c backups/state-TIMESTAMP-SUFFIX.sha256
jq '{lineage, serial, terraform_version, resources: [.resources[] | {type,name}]}' backups/state-TIMESTAMP-SUFFIX
# Preserve current state independently if present; don't overwrite your only copy.
# Use a unique directory for any forensic copies.
mkdir -m 700 backups/before-restore-UNIQUE
cp -p infra/home-assistant/terraform.tfstate backups/before-restore-UNIQUE/  # if present
# After confirming the snapshot belongs to this deployment and is the newest valid copy:
cp -p backups/state-TIMESTAMP-SUFFIX infra/home-assistant/terraform.tfstate
chmod 600 infra/home-assistant/terraform.tfstate
scripts/check.sh
tofu -chdir=infra/home-assistant state list
# Read/refresh only; inspect changes, don't apply them automatically.
tofu -chdir=infra/home-assistant plan -refresh-only
```

Compare lineage and serial with other copies. A stale snapshot can misidentify real resources. Check VM 130's actual config and disk IDs through the Proxmox administrator console before trusting it. A refresh-only plan does not save refreshed state unless applied; review that separately. Never restore while an apply is in flight. Avoid `state push -force` and manual JSON edits. If moving to another Mac, restore trusted CA and ignored `.env` with mode 600; initialize using the lock file.

## Lost state, surviving VM

Inspect VM 130's name, description, NIC MAC, disks and network before adoption. Obtain review before changing local state. Recover the most recent snapshot first. If no snapshot survives and the VM is confirmed to be this deployment, an operator can import only that VM:

```sh
# REVIEW REQUIRED: writes local state; does not recreate the VM.
tofu -chdir=infra/home-assistant import proxmox_virtual_environment_vm.home_assistant pve/130
tofu -chdir=infra/home-assistant plan
```

Reconcile import drift with the actual VM. A plan proposing disk replacement, EFI removal, deletion or VM replacement is a stop condition. Never import `pve/102` into this project. `prevent_destroy` blocks destructive plans while the resource remains in the configuration; removing the block/resource is not a recovery method. The initial `discover.sh` deliberately refuses an occupied VMID, so use direct reviewed plan commands for an existing, imported deployment.

## VM or application recovery

Use Home Assistant's built-in backup UI, copy backups off the VM, and test restoring onto a separately reviewed recovery VM/address. Keep encryption recovery keys outside the VM. For a full VM backup, an administrator may review a targeted `vzdump 130` operation to a suitable existing backup destination; never back up or delete all guests as a shortcut. A restored VM must not boot with the same static IP/MAC while the original runs.

For a lost VM with valid state, first inspect storage for surviving disks and decide whether to recover a full Proxmox backup or create a fresh HAOS instance and restore Home Assistant data. Do not recreate automatically. Retain state snapshots and the original prepared source. Rebuild requires the same static address checks, image staging and explicit review as initial deployment. Do not shrink disks. Infrastructure state does not restore integrations, secrets, history or dashboards.

## Failed first boot or interrupted apply

Keep the local state, failed plan and task logs private. Inspect whether VM 130 and its disks exist; do not rerun with another ID or delete it blindly. Run a direct reviewed plan to reconcile partial state. Check OVMF, Secure Boot keys disabled, `scsi0` boot order, `local` disk allocation and matching NIC MAC. In the graphical console use `ha network info`; if necessary use `login`, then `nmcli connection show` and `nmcli device show`. Verify `10.30.0.30/24`, gateway `10.30.0.1`, DNS `1.1.1.1` and manual IPv4. Never use DHCP on vmbr1.

Check Services egress and DNS through existing NAT rules without changing host networking. Tunnel problems are separate from HAOS boot: confirm SSH works, local port 8123 is free, and pve can reach `http://10.30.0.30:8123`. Use `ExitOnForwardFailure=yes`. Revoke only the dedicated `opentofu@pve!home-assistant` token if exposed. Leave ProxUI identity, VM 102 and host firewall/networking untouched.
