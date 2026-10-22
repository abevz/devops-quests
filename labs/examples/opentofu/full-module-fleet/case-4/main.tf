variable "components" {
  type    = map(object({ name = string, port = optional(number, 8080), labels = optional(map(string), {}) }))
  default = { a = { name = "api-dev" }, b = { name = "api-prod", port = 9090, labels = { env = "prod" } } }
}
module "worker" {
  source   = "./modules/worker"
  for_each = var.components
  name     = each.value.name
  settings = { port = each.value.port, labels = each.value.labels }
}
output "names" { value = { for k, m in module.worker : k => m.name } }
