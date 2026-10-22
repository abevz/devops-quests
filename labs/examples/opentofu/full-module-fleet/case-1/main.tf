module "worker" {
  source   = "./modules/worker"
  for_each = toset(["api", "jobs"])
  name     = each.key
}
output "labels" {
  value = { for k, v in module.worker : k => v.label }
}
