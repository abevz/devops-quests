variable "environment" {
  type    = string
  default = "dev"
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Use dev, test or prod."
  }
}
variable "services" {
  type    = map(object({ enabled = bool }))
  default = { api = { enabled = true }, docs = { enabled = false } }
}
locals { active = { for name, service in var.services : name => service if service.enabled } }
resource "terraform_data" "service" {
  for_each = local.active
  input    = "${var.environment}/${each.key}"
}
output "active" { value = { for key, value in terraform_data.service : key => value.output } }
