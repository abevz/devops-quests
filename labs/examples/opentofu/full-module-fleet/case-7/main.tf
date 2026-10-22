module "worker" {
  source = "./modules/worker"
  count  = 2
  name   = "worker-${count.index}"
}
output "names" { value = module.worker[*].name }
