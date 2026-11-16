# Cluster setup

## Scope and versions

The Mac is the control machine and holds state at `infra/home-assistant/terraform.tfstate`. Run commands from the repository root. Use OpenTofu 1.13.x (locally tested 1.13.9); provider `bpg/proxmox = 0.112.0`. Keep `infra/home-assistant/.terraform.lock.hcl` in Git and review changes to it. Provider binaries are ignored. Version 0.112.0's established VM resource is `proxmox_virtual_environment_vm`; the similarly named `proxmox_vm` is experimental in this release and is not used.

The image is pinned to [HAOS 18.4](https://github.com/home-assistant/operating-system/releases/tag/18.4), including its official GitHub asset SHA256. HAOS 18.5 is a Raspberry Pi only release and has no KVM image. The pin is deliberate; upgrades require separate review, a fresh image manifest and a plan. Do not replace an existing HAOS boot disk to perform a normal OS update: use HAOS's supported updater and take backups.

Provider fields were checked against the [versioned VM documentation](https://github.com/bpg/terraform-provider-proxmox/blob/v0.112.0/docs/resources/virtual_environment_vm.md) and [provider authentication documentation](https://github.com/bpg/terraform-provider-proxmox/blob/v0.112.0/docs/index.md). `disk.import_from` uses an **uncompressed** `local:import/*.qcow2` file through the API, so no privileged provider SSH configuration is needed.

## Administrator discovery before any changes

The following commands are read-only; run in an administrator shell on pve. They are not automated host setup. The currently configured `pve` SSH alias uses `tobin`, who lacks storage access and sudo. Choose an existing authorized administrator session; do not enable root SSH merely for this project.

```sh
pveversion
pvesm status
pvesh get /storage/local --output-format json-pretty
pvesh get /nodes/pve/storage/local/status --output-format json-pretty
pvesh get /cluster/resources --type vm --output-format json-pretty
qm config 102
ip -4 address show vmbr1
ip route
```

`local` must be enabled, active, available on pve and directory storage supporting both **images** (VM and EFI disks) and **import** (the source QCOW2). The script conservatively requires 40 GiB available; also allow room for the prepared source, growth, temporary files and backups. If storage isn't `dir`, stop and review an adapted design. No `local-lvm` is assumed.

If `images` or `import` is absent, this is a **review blocker**. After separately approving a storage-content change, an administrator can preserve all current content types while adding the missing ones:

```sh
# HOST MUTATION — review the existing storage configuration first; do not run yet.
content=$(pvesh get /storage/local --output-format json | jq -r '.content | split(",") + ["images","import"] | unique | join(",")')
pvesm set local --content "$content"
```

This requires `jq` on the host, or use Datacenter → Storage → local → Edit and retain every existing selection. Never change the storage path or disable existing content. The project does not execute this command.

Check VMID 130 across **all nodes and containers**, not just guests visible to the restricted token. Review the inventory for the proposed MAC `BC:24:11:30:00:30` as well. Do not import VM 102. Before creating or booting HAOS, verify IP availability on the Services segment:

```sh
# Read-only network probes from pve, not from the unrouted Mac.
command -v arping
arping -D -I vmbr1 -c 3 -w 5 10.30.0.30
ip neigh show dev vmbr1
```

Use **iputils arping**, where `-D` returns zero if no duplicate replies arrived. If absent, stop; review `apt-get install iputils-arping` separately. No ping reply does not prove an address is unused. Check your address inventory and powered-off VM/container configuration too; guests can hold static addresses inside their disks. Reserve `10.30.0.30` for HAOS in your inventory only after this review. Stop on a duplicate or inconclusive result. Repeat immediately before a reviewed apply.

### Privileged preflight without administrator SSH

The Mac has no root SSH to pve, and root SSH must not be enabled for this project. The privileged checks therefore live in `scripts/pve-preflight.sh`, which an administrator runs as root in the Proxmox web UI shell (**Datacenter → pve → Shell**). It is read-only: full VM/container inventory and VMID 130 absence across all node directories, the proposed MAC in guest configs, `arping -D` for `10.30.0.30` and, when given an image ID, the staged file's SHA256 and `qemu-img check`. Copy it over with the unprivileged SSH user, then let root review and take its own copy so a user-writable file is not executed as root:

```sh
# Mac
shasum -a 256 scripts/pve-preflight.sh
scp scripts/pve-preflight.sh pve:pve-preflight.sh
# Root shell on pve: compare the SHA256 and read the script before running it.
install -m 700 -o root -g root /home/tobin/pve-preflight.sh /root/pve-preflight.sh
sha256sum /root/pve-preflight.sh
bash /root/pve-preflight.sh                  # initial discovery
bash /root/pve-preflight.sh 'local:import/haos-18.4-static-SHA256.qcow2'   # after staging
```

It ends with a line such as `PREFLIGHT-OK vmid=130 ip=10.30.0.30 image=none time=1763300000`. `discover.sh` and `plan.sh` prompt for that line and reject it if it covers a different image or is more than an hour old. Pasting it is an operator attestation, not cryptographic proof: read the preceding output. The preflight fails if VMID 130 exists, so it is intentionally an **initial creation** preflight; later maintenance requires inspection of the existing VM and state instead.

## Dedicated API identity (review, then administrator executes)

Do not use `proxui@pve`, a root API token or root password. The commands below create a dedicated PVE user and privilege-separated token. These commands are **host mutations, not executed by this scaffold**. Re-running `user add`, `role add` or `token add` can fail if already present: inspect `pveum user list`, `pveum role list` and `pveum user token list opentofu@pve` first; do not rotate existing credentials blindly.

```sh
pveum user add opentofu@pve --comment 'Home-Cluster HAOS OpenTofu only'
pveum role add HAOSVM --privs 'VM.Allocate VM.Audit VM.Config.CPU VM.Config.Memory VM.Config.Disk VM.Config.HWType VM.Config.Options VM.Config.Network VM.PowerMgmt'
pveum role add HAOSStorage --privs 'Datastore.Audit Datastore.AllocateSpace'
pveum role add HAOSNodeAudit --privs 'Sys.Audit'
pveum role add HAOSBridge --privs 'SDN.Use SDN.Audit'
pveum user token add opentofu@pve home-assistant --privsep 1

# Apply identical scoped ACLs to BOTH the user and token: effective rights intersect.
pveum acl modify /vms/130 --users opentofu@pve --roles HAOSVM
pveum acl modify /vms/130 --tokens 'opentofu@pve!home-assistant' --roles HAOSVM
pveum acl modify /storage/local --users opentofu@pve --roles HAOSStorage
pveum acl modify /storage/local --tokens 'opentofu@pve!home-assistant' --roles HAOSStorage
pveum acl modify /nodes/pve --users opentofu@pve --roles HAOSNodeAudit
pveum acl modify /nodes/pve --tokens 'opentofu@pve!home-assistant' --roles HAOSNodeAudit
pveum acl modify /sdn/zones/localnetwork/vmbr1 --users opentofu@pve --roles HAOSBridge
pveum acl modify /sdn/zones/localnetwork/vmbr1 --tokens 'opentofu@pve!home-assistant' --roles HAOSBridge
```

Copy the one-time secret directly into ignored `.env`, in the format `PROXMOX_VE_API_TOKEN='opentofu@pve!home-assistant=SECRET'`. Avoid terminal recording and shell history containing secrets. Never write credentials into tfvars, code or plan arguments. This deployment identity has no ACL on VM 102 or host configuration. `VM.Allocate` also permits deletion of VM 130: `prevent_destroy` is an additional configuration guard, not a substitute for ACLs or backups. Storage allocation permissions apply to all of `local`, so the identity is restricted but not a per-file storage sandbox.

These privileges cover the planned create/configure/start/import workflow; they have **not** been tested against authenticated API calls here. Inspect specific 403 responses and grant only a justified scoped privilege. Do not copy the provider's broad example role or grant Administrator at `/`. Node audit permits reading node status/tasks, not modifying networking. Administrator staging avoids granting `Sys.Modify` and download/upload privileges to OpenTofu. No `VM.Config.Cloudinit`, clone, migration, host network modification or guest-agent command privileges are required. Optional console/backup operations use your administrator session rather than this token.

Check effective permissions using the [Proxmox user management documentation](https://pve.proxmox.com/pve-docs/pveum.1.html) and API viewer for the installed PVE version:

```sh
pveum user permissions opentofu@pve
pveum user token permissions opentofu@pve home-assistant
```

Verify the token cannot configure `/vms/102` and cannot change host networking. Privileged discovery runs as root in the web UI shell (`pve-preflight.sh`) because an ACL-filtered guest list cannot establish that a VMID is unused.

## API TLS trust

Obtain the public `/etc/pve/pve-root-ca.pem` certificate through an existing trusted administrator session. Compare its fingerprint on pve before trusting it on the Mac. Store the public certificate in an ignored local file and set its absolute path as `SSL_CERT_FILE` in `.env`. Check that the endpoint certificate includes the IP address in its SAN. A CA trust file does not fix a name mismatch. `SSL_CERT_FILE` replaces the system trust store, so `check.sh` unsets it for `tofu init`, the only step that contacts the provider registry. For a separately reviewed local PoC, set `TF_VAR_insecure=true` in `.env` to make both provider and discovery skip verification. This is explicit, defaults off, and does not change the host certificate.

## Prepare the official image on the Mac

Install local dependencies if absent (not run automatically):

```sh
brew install qemu mtools xz jq
scripts/prepare-image.sh
```

The script needs `qemu-img`, `mcopy`, `mmd`, `mdir`, Python 3, curl and shasum on PATH. Prefer Homebrew QEMU over an unrelated Android SDK binary. Allow at least 15 GiB temporary space. It downloads the pinned official `.qcow2.xz`, verifies SHA256 **before decompression**, checks QCOW2 integrity, converts to a sparse raw file, reads GPT to locate only `hassos-boot`, and writes `CONFIG/network/home-assistant.nmconnection` with mtools. It reads the profile back, reconverts to QCOW2, checks integrity, and prints the final import ID. It never mounts a Mac or host device and never connects to Proxmox.

The official source SHA256 is `756ec485b1b153099ca53e88a5eebd63a801d56b791afe5c6d63ef94a35dc02d`, from the [official 18.4 release metadata](https://api.github.com/repos/home-assistant/operating-system/releases/tags/18.4). The customized image has a different SHA256 and a content-addressed filename. Preserve `artifacts/image-manifest.txt`, `artifacts/prepared.sha256` and the prepared image with backups. Binary hashes may differ between runs/tool versions because of filesystem timestamps; the provisioned network settings are reproducible. Retained `artifacts/prepare.*` directories are safe to inspect and manually remove when no process is using them. Re-running uses a fresh local working copy and does not edit a staged image.

HAOS is **not cloud-init**. The [supported boot-partition CONFIG import](https://contributors.home-assistant.io/os/operating-system/configuration/) is read before normal use and consumed/deleted after import. It installs a persistent NetworkManager connection. The profile is bound to the configured MAC, has a stable UUID, IPv4 `method=manual`, `address1=10.30.0.30/24,10.30.0.1`, DNS `1.1.1.1`, and IPv6 disabled. See [HAOS networking](https://contributors.home-assistant.io/os/operating-system/networking/). No DHCP setting or Proxmox `initialization` block is used. First-boot import and ordering must still be verified on the deployed version using the console; stop if the prepared profile is not imported.

## Stage the prepared image — only after review

This is an explicit host file upload, outside OpenTofu, and **not authorized for this initial session**. Use the image basename and SHA from `prepared.sha256`; substitute them below. On pve, inspect `pvesm path` to determine the actual import directory; don't assume `/var/lib/vz`. The import file is an immutable input, not an additional managed workload.

```sh
# Mac: review these values first.
cat artifacts/prepared.sha256
cat artifacts/image-manifest.txt
# Administrator on pve: resolve the destination, and create its import directory
# ONLY if required and approved. Do not overwrite an existing image.
pvesm path 'local:import/haos-18.4-static-SHA256.qcow2'
# Mac: upload with the unprivileged SSH user to a temporary filename on pve.
scp artifacts/haos-18.4-static-SHA256.qcow2 pve:/tmp/haos-upload.qcow2
# Administrator on pve: use the reviewed exact path from pvesm path above.
sha256sum /tmp/haos-upload.qcow2
qemu-img check -f qcow2 /tmp/haos-upload.qcow2
# Compare SHA256 with prepared.sha256. Then, after reviewing DEST:
DEST=$(pvesm path 'local:import/haos-18.4-static-SHA256.qcow2')
# Fail if the destination exists; don't overwrite sources used by other plans.
test ! -e "$DEST" && cp -n /tmp/haos-upload.qcow2 "$DEST"
sha256sum "$DEST"
pvesm list local --content import
```

Replace `SHA256` with the actual value, including in `DEST`. The copy into `DEST` runs as root in the web UI shell; the checksum comparison guards against changes while the upload sat in `/tmp`. If the import directory doesn't exist, review creating exactly that directory before copying. Verify both checksums match. Keep the prepared source available for rebuilds. OpenTofu imports it into a new disk owned by VM 130; it does not attach the source as the writable guest disk. The 32 GiB resize allows HAOS to expand its data partition during boot.

## Plan, review, and stop

```sh
cp .env.example .env
chmod 600 .env
# Edit .env with the real token and TLS settings.
cp infra/home-assistant/terraform.tfvars.example infra/home-assistant/terraform.tfvars
# Edit image_file_id using the output from preparation.
scripts/check.sh
scripts/discover.sh
scripts/plan.sh
```

Do not recopy examples over an existing local configuration. Through the API, the plan script checks datastore capabilities, free space, bridge presence and that the staged source exists. It then prompts for a fresh `PREFLIGHT-OK` line from `pve-preflight.sh` run with the same image ID, which covers full VMID inventory, ARP duplicates and the staged checksum. Before approval, reconcile offline address allocations and confirm the source manifest, static profile and MAC match. Review `tofu show artifacts/home-assistant.tfplan` using `-chdir=infra/home-assistant`. The initial plan must contain exactly **one VM create**, ID 130, no updates/deletes/replacements, and no reference to VM 102. No upload, host network/firewall, user or storage resources should appear. A plan itself does not verify guest readiness or prove IP availability.

**Stop here for this task.** `scripts/apply.sh` always fails, and no apply has been run. After explicit review and authorization in a later session, rerun discovery immediately, regenerate/review the plan if anything changed, and an operator may execute:

```sh
# FUTURE ONLY — requires review and authorization, not part of this setup.
tofu -chdir=infra/home-assistant apply ../../artifacts/home-assistant.tfplan
scripts/backup-state.sh
scripts/status.sh
```

State backup before subsequent changes: `scripts/backup-state.sh`. It fails clearly before the first state exists. Serialize all OpenTofu operations; never run backup/restore concurrently with apply. Keep plans private: they may contain sensitive values and are ignored.

## Verify after a future approved deployment

Use the Proxmox graphical console for VM 130 and run `ha network info`. Confirm the static IPv4, gateway and DNS, and check `ha core info`. The QEMU agent is disabled in the provider to avoid bootstrap waits; the output URL is intended configuration, not agent-discovered readiness. If bootstrap fails, at the HA console use `login` for the host shell and inspect `nmcli connection show` and `nmcli device show`; the profile should be manual and match the MAC. A console recovery can use `ha network update INTERFACE --ipv4-method static --ipv4-address 10.30.0.30/24 --ipv4-gateway 10.30.0.1 --ipv4-nameserver 1.1.1.1` after identifying the interface with `ha network info`. Do not switch to DHCP.

From the Mac:

```sh
scripts/status.sh
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8123:10.30.0.30:8123 pve
```

Visit [http://localhost:8123](http://localhost:8123), complete onboarding and create a Home Assistant backup. Initial HA container downloads require the existing Services NAT/DNS path and can take time. If egress or the tunnel is blocked, report the exact failure and review current rules; do not replace host Wi-Fi, bridge, NAT or firewall configuration. Confirm VM 102 is still reachable through its existing access method.
