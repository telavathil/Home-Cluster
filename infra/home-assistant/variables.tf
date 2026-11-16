variable "insecure" {
  description = "Explicit PoC opt-in to skipping API TLS verification; prefer SSL_CERT_FILE."
  type        = bool
  default     = false
}

variable "image_file_id" {
  description = "Reviewed, prepared QCOW2 already staged in local:import; use its SHA256 in the filename."
  type        = string
  validation {
    condition     = can(regex("^local:import/haos-18\\.4-static-[0-9a-f]{64}\\.qcow2$", var.image_file_id))
    error_message = "Use the content-addressed local:import ID printed by prepare-image.sh."
  }
}

variable "disk_size_gb" {
  type        = number
  default     = 32
  description = "HAOS boot/data disk size in GiB; shrinking is unsupported."
  validation {
    condition     = var.disk_size_gb >= 32 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "Disk must be an integer of at least 32 GiB."
  }
}
