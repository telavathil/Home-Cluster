output "vm_id" {
  value = proxmox_virtual_environment_vm.home_assistant.vm_id
}
output "home_assistant_url" {
  description = "Open after starting the SSH tunnel; address is intended configuration, not a readiness probe."
  value       = "http://localhost:8123"
}
output "ssh_tunnel" {
  value = "ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8123:10.30.0.30:8123 pve"
}
