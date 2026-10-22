variable "name" { default = "api" }
locals {
  label = "${var.name}-dev"
}
resource "terraform_data" "service" {
  input = local.label
}
output "label" { value = terraform_data.service.output }
