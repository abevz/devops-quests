variable "port" {
  default = 2048
  validation {
    condition     = floor(var.port) == var.port
    error_message = "port must be an integer."
  }
}
output "port" { value = var.port }
