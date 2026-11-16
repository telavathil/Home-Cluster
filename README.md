# Home-Cluster

Documentation and infrastructure-as-code for a single-node Proxmox VE home cluster. The cluster is the host `pve` and the guests it runs. Each workload is documented here, and only the workloads listed as managed are under this repository's OpenTofu control. Facts below were gathered on 2026-11-16 from read-only API, root web-shell and `tobin` SSH checks.

## Host

| | |
|---|---|
| Node | `pve`, Proxmox VE 9.2.26 (kernel 7.0.14-28-pve) |
| Hardware | 8 CPU threads, 62 GiB RAM, 1 TB WD NVMe (`nvme0n1`) |
| Management | Web UI and API at `https://192.168.1.40:8006`. The API certificate is issued by the cluster's own CA and covers `192.168.1.40` |
| Storage | `local`: directory storage at `/var/lib/vz` for `images`, `import`, `iso`, `vztmpl`, `rootdir`, `snippets` and `backup` (~857 GB free) |

## Networks

| Interface | Address | Role |
|---|---|---|
| `wlp170s0` (Wi-Fi) | `192.168.1.40/24`, gateway `192.168.1.1` | Uplink to the home LAN. The host's address comes from DHCP on this network |
| `vmbr1` | `10.30.0.1/24` | Services network ("Docker and LXC"). No physical port: guests reach the internet through NAT on the host. No DHCP server runs on the host |
| `vmbr2` | `10.40.0.1/24` | Lab network ("isolated VMs"). Only VM 101 is attached |

LAN devices have no route to the guest networks; they reach only the ports the host forwards (see [Host firewall and NAT](#host-firewall-and-nat)). Everything else is reached through SSH to `pve` (`Host pve` in `~/.ssh/config`: `192.168.1.40`, user `tobin`, no sudo). Root access is through the Proxmox web UI shell only: root SSH is deliberately not enabled.

## Host firewall and NAT

The host's own rules live in `/etc/nftables/homelab.nft`, loaded by `homelab-nftables.service`. The stock `nftables.service` is disabled. On start, the service deletes the `inet homelab_filter` and `ip homelab_nat` tables and then loads the file, so a restart is idempotent and loads exactly what boot loads. Proxmox's own firewall service is active with no rules configured.

| Table / chain | Rules |
|---|---|
| `homelab_filter` input | Guests may ping their gateway and receive replies to host-initiated connections. Only ProxUI (`10.30.0.20`) may reach the host, and only the API on port 8006. All other guest traffic to the host is dropped |
| `homelab_filter` forward | Established traffic is allowed. New guest traffic to private ranges (`10/8`, `172.16/12`, `192.168/16`) is dropped, and guests may route out only through `wlp170s0` |
| `homelab_nat` postrouting | `vmbr1` and `vmbr2` are masqueraded out through `wlp170s0` |
| `homelab_nat` prerouting | **Port forward:** `iifname "wlp170s0" tcp dport 8123 dnat to 10.30.0.30:80`, so LAN devices reach Home Assistant at `http://192.168.1.40:8123`. Added 2026-11-16 |

The forward matches the Wi-Fi interface rather than the host's address, so it survives a DHCP address change. Replies pass the forward chain's established rule before the private-range drop, and nothing else on `vmbr1` becomes reachable from the LAN.

These rules are not managed by OpenTofu. Change them only with explicit approval, in the root web shell:

```sh
cp -a /etc/nftables/homelab.nft /etc/nftables/homelab.nft.bak-YYYYMMDD   # back up first
# edit /etc/nftables/homelab.nft (a second `table ip homelab_nat { ... }` block merges into the table)
nft -c -f /etc/nftables/homelab.nft && echo SYNTAX_OK                     # never skip
systemctl restart homelab-nftables && systemctl is-active homelab-nftables
nft list ruleset
```

Always run the syntax check first: the service deletes both tables before loading, so a file that fails to load leaves guests with no NAT and no filtering. To undo the Home Assistant forward, restore the pre-change backup `/etc/nftables/homelab.nft.bak-20261116` (or delete the appended `prerouting` block) and restart the service.

## Guests

| VMID | Name | Network | Address | State | Managed by |
|---|---|---|---|---|---|
| 100 | `debian-services-test` | `vmbr1` | Unknown: any static address is inside its disk | Stopped | Not in this repo |
| 101 | `debian-lab-test` | `vmbr2` | Not recorded | Stopped | Not in this repo |
| 102 | `proxui` | `vmbr1` | `10.30.0.20` | Running | Not in this repo (own identities `proxui@pve`, `proxui-console@pve`) |
| 130 | `home-assistant` | `vmbr1` | `10.30.0.30` (static) | Running | **This repo**: [Home Assistant](docs/HOME_ASSISTANT.md) |
| 9000 | `debian-13-template` | `vmbr1` | DHCP via cloud-init | Template | Not in this repo |

Clones of template 9000 on `vmbr1` request DHCP, but nothing on the host serves it. Keep VM 100 and any new guest off `10.30.0.30`.

## Access from the Mac

| Service | Open | Tunnel | Always-on |
|---|---|---|---|
| Proxmox | `https://192.168.1.40:8006` | Direct, on the home LAN | n/a |
| ProxUI | [http://localhost:8081](http://localhost:8081) | `proxui-ui` host: jumps through `pve` to the VM, forwards to its `127.0.0.1:8080` | LaunchAgent `com.homecluster.proxui-tunnel` |
| Home Assistant | [http://localhost:8123](http://localhost:8123) | `home-assistant-ui` host: ends at `pve`, forwards to `10.30.0.30:80` | LaunchAgent `com.homecluster.home-assistant-tunnel` |
| Home Assistant (any LAN device, e.g. the phone app) | `http://192.168.1.40:8123` | None: the host's port forward | Always on |

The SSH hosts are in `~/.ssh/config` and the agents in `~/Library/LaunchAgents/`, outside this repository. Tunnels bind to `127.0.0.1` only. Plain SSH to ProxUI is `ssh proxui`. Home Assistant has no SSH login.

## What this repository manages

- **OpenTofu:** only VM 130, with local state on the Mac and a dedicated, narrowly scoped API token. See [Home Assistant](docs/HOME_ASSISTANT.md).
- **Not managed:** the host itself, bridges, Wi-Fi, NAT and firewall rules (documented above), storage configuration, identities, and every other guest. Changes to these are manual and reviewed. Never import VM 102 or `proxui@pve` into this project.

## Docs

- [Home Assistant](docs/HOME_ASSISTANT.md): workload summary, workflow, access and validation record.
- [Home Assistant setup](docs/HOME_ASSISTANT_SETUP.md): the administrator procedure (discovery, API identity, TLS trust, image staging, plan review, verification).
- [Recovery](docs/RECOVERY.md): OpenTofu state backup/restore and Home Assistant recovery.
- [Documentation backlog](docs/TODO.md): hand-built parts of the cluster (users, roles, ProxUI, host setup) still to be written down.
