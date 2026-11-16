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
| `vmbr1` | `10.30.0.1/24` | Services network. No physical port: guests reach the internet through existing NAT on the host. No DHCP server runs on the host |
| `vmbr2` | `10.40.0.1/24` | Separate lab network. Only VM 101 is attached |

The Mac has no route to the guest networks. Everything is reached through SSH to `pve` (`Host pve` in `~/.ssh/config`: `192.168.1.40`, user `tobin`, no sudo). Root access is through the Proxmox web UI shell only: root SSH is deliberately not enabled.

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

The SSH hosts are in `~/.ssh/config` and the agents in `~/Library/LaunchAgents/`, outside this repository. Tunnels bind to `127.0.0.1` only. Plain SSH to ProxUI is `ssh proxui`. Home Assistant has no SSH login.

## What this repository manages

- **OpenTofu:** only VM 130, with local state on the Mac and a dedicated, narrowly scoped API token. See [Home Assistant](docs/HOME_ASSISTANT.md).
- **Not managed:** the host itself, bridges, Wi-Fi, NAT, firewall, storage configuration, identities, and every other guest. Changes to these are manual and reviewed. Never import VM 102 or `proxui@pve` into this project.

## Docs

- [Home Assistant](docs/HOME_ASSISTANT.md): workload summary, workflow, access and validation record.
- [Home Assistant setup](docs/HOME_ASSISTANT_SETUP.md): the administrator procedure (discovery, API identity, TLS trust, image staging, plan review, verification).
- [Recovery](docs/RECOVERY.md): OpenTofu state backup/restore and Home Assistant recovery.
