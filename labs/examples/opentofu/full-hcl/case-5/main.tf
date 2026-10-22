terraform {
  required_version = ">= 1.4.0"
}

variable "environment" {
  type    = string
  default = "dev"

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be dev, test, or prod."
  }
}

variable "services" {
  type = map(object({
    port    = number
    enabled = bool
  }))
  default = {
    api  = { port = 8080, enabled = true }
    docs = { port = 8081, enabled = false }
  }
}

locals {
  active_services = {
    for name, service in var.services : name => service
    if service.enabled
  }

  service_names = {
    for name, service in local.active_services : name => "${var.environment}-${name}"
  }
}

resource "terraform_data" "service" {
  for_each = local.active_services

  input = {
    name = local.service_names[each.key]
    port = each.value.port
  }
}

resource "terraform_data" "summary" {
  input = [for service in terraform_data.service : service.output.name]
}

output "service_names" {
  value = terraform_data.summary.output
}
