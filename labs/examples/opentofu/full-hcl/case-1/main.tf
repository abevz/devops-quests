locals {
  name = "api"
  port = 8080
}
output "endpoint" {
  value = "${local.name}:${local.port}"
}
