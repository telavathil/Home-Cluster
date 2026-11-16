# Authentication comes only from PROXMOX_VE_API_TOKEN in the shell environment.
provider "proxmox" {
  endpoint = "https://192.168.1.40:8006/"
  insecure = var.insecure
}
