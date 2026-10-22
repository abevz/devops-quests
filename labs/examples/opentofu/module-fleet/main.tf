variable "services" {
  type    = set(string)
  default = ["api", "worker"]
}
module "service" {
  source   = "./modules/service"
  for_each = var.services
  name     = each.key
}
output "names" { value = { for key, value in module.service : key => value.name } }
