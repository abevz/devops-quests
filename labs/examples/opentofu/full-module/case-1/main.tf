module "worker" {
  source = "./modules/worker"
  name   = "api"
}
output "label" {
  value = module.worker.label
}
