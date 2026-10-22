variable "replicas" {
  default = 2
  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be positive."
  }
}
output "replicas" { value = var.replicas }
