variable "name" { type = string }
module "worker" {
  source = "./modules/worker"
  name   = var.name
}
output "worker_name" { value = module.worker.name }
output "worker_id" { value = module.worker.id }
output "worker_token" {
  value     = module.worker.token
  sensitive = true
}
