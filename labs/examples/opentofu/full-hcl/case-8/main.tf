variable "listen_port" {
  type    = number
  default = 2048
  validation {
    condition     = floor(var.listen_port) == var.listen_port && var.listen_port >= 1024 && var.listen_port <= 65535
    error_message = "listen_port must be an integer in 1024..65535."
  }
}
output "listen_port" { value = var.listen_port }
