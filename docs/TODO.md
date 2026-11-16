# Documentation backlog

Things on the cluster that were set up by hand and are not yet written down. For each item, record the facts in the README or a workload page, mark facts that were not verified, and tick it off. Gather facts read-only: unless noted, run the commands as root in the Proxmox web UI shell. Never copy secrets (token values, passwords, Wi-Fi keys) into the repository; record only where they are kept.

## Proxmox users, roles and tokens

- [ ] **Every user**: realm, purpose, enabled state, expiry, and whether it has a password or only tokens. Known so far: `root@pam`, `proxui@pve` (ProxUI VM management service), `proxui-console@pve` (disabled), `opentofu@pve` (documented). `pveum user list`
- [ ] **Custom roles and their privileges**, especially the ones ProxUI uses. Only the `HAOS*` roles are documented. `pveum role list --output-format json-pretty`, keeping only roles with `special: 0`
- [ ] **Every ACL entry**: path, user or token, role, propagate. `pveum acl list`
- [ ] **API tokens**: owner, privilege separation, expiry, comment, and the token's effective permissions. `pveum user token list proxui@pve`, `pveum user token permissions proxui@pve <tokenid>`
- [ ] **Why `proxui-console@pve` exists and why it is disabled.** Decide whether to keep it
- [ ] **Who rotates the ProxUI token, and how** (procedure, plus where the secret lives inside the ProxUI VM)

## ProxUI (VM 102)

- [ ] **VM hardware and settings**: CPU, RAM, disks, MAC, boot and start options, protection. `qm config 102`
- [ ] **Guest OS and its network**: distribution and version, static `10.30.0.20` configuration, gateway and DNS. `ssh proxui 'cat /etc/os-release; ip -4 addr; ip route; resolvectl status'` (as `tobin`)
- [ ] **How ProxUI is installed and run**: source repository and version, service unit or Compose file, config file locations, and why it listens on `127.0.0.1:8080` only. `ssh proxui 'systemctl list-units --type=service --state=running'`
- [ ] **How it talks to Proxmox**: API endpoint, TLS trust, and which token it uses. The host firewall allows only `10.30.0.20` to reach `192.168.1.40:8006`
- [ ] **Its own authentication** and who has accounts. This is a prerequisite for any LAN port forward
- [ ] **Guest-level hardening**: SSH users and keys (`tobin`), sudo, firewall, updates. Also why systemd-resolved's LLMNR (port 5355) is listening on all interfaces
- [ ] **Backup and restore** for the VM and for ProxUI's data
- [ ] **Decide on LAN access**: either keep only the tunnel, or bind ProxUI to `10.30.0.20` and add a host forward restricted with `ip saddr`. ProxUI currently listens on `127.0.0.1:8080` only, so a host forward cannot reach it yet

## Host `pve`

- [ ] **Installation**: ISO and version, install date, disk layout and filesystem, hostname. `lsblk -f`, `pveversion -v`
- [ ] **Package repositories and update routine**: enterprise or no-subscription. `cat /etc/apt/sources.list.d/*`
- [ ] **Wi-Fi uplink**: what manages `wlp170s0` (wpa_supplicant, NetworkManager or ifupdown), and where its configuration lives (without the key). `systemctl status wpa_supplicant NetworkManager`, `ls /etc/wpa_supplicant`
- [ ] **Router side**: DHCP reservation for `192.168.1.40`, and any router settings this cluster depends on
- [ ] **Bridges `vmbr1` and `vmbr2`**: created in `/etc/network/interfaces` with comments "Services - Docker and LXC" and "Lab - isolated VMs". Record why `vmbr2` is isolated and its intended use
- [ ] **IP forwarding**: where `net.ipv4.ip_forward=1` is set persistently. `grep -r ip_forward /etc/sysctl.conf /etc/sysctl.d/`
- [ ] **`homelab-nftables.service`**: the full unit file, and when and why it replaced the stock `nftables.service`. `systemctl cat homelab-nftables`. The rules are documented in the README
- [ ] **Proxmox firewall**: it is active with no rules. Record whether that is intentional. `pve-firewall status`, `ls /etc/pve/firewall`
- [ ] **The `tobin` host user**: how it was created, SSH key authentication, no sudo, group memberships. `id tobin`, `ls -l /home/tobin/.ssh`
- [ ] **Root access policy**: web UI login, root SSH disabled, where the root password is kept. `grep -iE '^(PermitRootLogin|PasswordAuthentication)' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*`
- [ ] **Packages added by hand**: `iputils-arping` (2026-11-16, for preflight) and anything else. `grep ' install ' /var/log/apt/history.log`
- [ ] **Certificates**: the self-signed cluster CA, the node certificate's expiry and renewal. `openssl x509 -in /etc/pve/local/pve-ssl.pem -noout -enddate`
- [ ] **Time and DNS** on the host. `timedatectl`, `cat /etc/resolv.conf`
- [ ] **Backups**: any `vzdump` jobs, where they go, and retention (`local` keeps all). `cat /etc/pve/jobs.cfg`

## Other guests

- [ ] **VM 100 `debian-services-test`**: purpose, OS, its static address inside the disk (to keep it off `10.30.0.30`), and whether to keep it
- [ ] **VM 101 `debian-lab-test`**: purpose, address on `vmbr2`, and whether to keep it
- [ ] **Template 9000 `debian-13-template`**: how it was built (cloud image or ISO, cloud-init user and keys), and the fact that clones request DHCP that nothing on `vmbr1` serves

## Mac control machine

- [ ] **`~/.ssh/config` hosts** (`pve`, `proxui`, `proxui-ui`, `home-assistant-ui`) and the keys they use
- [ ] **LaunchAgents** `com.homecluster.proxui-tunnel` and `com.homecluster.home-assistant-tunnel`: what they run, their logs, and how to restart them. The Home Assistant one is documented
- [ ] **Keychain trust** for the Proxmox CA, restricted to SSL for `192.168.1.40` (documented in the Home Assistant setup), and how to undo it
- [ ] **What the Mac holds that must be backed up off-device**: `.env`, `terraform.tfvars`, `pve-root-ca.pem`, `backups/` and `artifacts/`

## Home Assistant follow-ups

- [ ] Run `ha network info` in the VM 130 console and record the result
- [ ] Take a first Home Assistant backup and record where copies are kept
- [ ] Next reviewed apply: refresh the stale `ssh_tunnel` output in local state
