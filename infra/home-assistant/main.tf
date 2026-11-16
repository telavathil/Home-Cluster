# The source QCOW2 contains a supported HAOS CONFIG/network keyfile.
# No cloud-init initialization block: HAOS does not consume cloud-init.
resource "proxmox_virtual_environment_vm" "home_assistant" {
  node_name       = "pve"
  vm_id           = 130
  name            = "home-assistant"
  description     = "Home Assistant OS 18.4; managed by Home-Cluster OpenTofu"
  tags            = ["opentofu", "home-assistant"]
  bios            = "ovmf"
  machine         = "q35"
  scsi_hardware   = "virtio-scsi-single"
  boot_order      = ["scsi0"]
  started         = true
  on_boot         = true
  stop_on_destroy = false
  # Proxmox-side deletion guard, complementing prevent_destroy below.
  protection = true

  cpu {
    cores = 2
    type  = "host"
  }
  memory {
    dedicated = 4096
    floating  = 0
  }
  agent {
    enabled = false
  }
  efi_disk {
    datastore_id      = "local"
    file_format       = "raw"
    type              = "4m"
    pre_enrolled_keys = false
  }
  disk {
    datastore_id = "local"
    import_from  = var.image_file_id
    interface    = "scsi0"
    file_format  = "qcow2"
    size         = var.disk_size_gb
    iothread     = true
    discard      = "on"
  }
  network_device {
    bridge      = "vmbr1"
    model       = "virtio"
    mac_address = "BC:24:11:30:00:30"
  }
  operating_system {
    type = "l26"
  }
  lifecycle {
    prevent_destroy = true
  }
}
