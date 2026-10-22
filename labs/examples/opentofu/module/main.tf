module "api" {
  source = "./modules/service"
  name   = "api"
}
output "name" { value = module.api.name }
