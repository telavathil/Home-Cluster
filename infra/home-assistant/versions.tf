terraform {
  required_version = ">= 1.13.0, < 1.14.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "= 0.112.0"
    }
  }
  backend "local" {
    path = "terraform.tfstate"
  }
}
