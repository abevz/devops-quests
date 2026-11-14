set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
variable "hub" {
 type = string
 default = "dispatch"
}
locals { hub = var.hub }
module "north" {
 source = "./modules/station"
 name = "north"
 upstream = local.hub
}
module "south" {
 source = "./modules/station"
 name = "south"
 upstream = module.north.route
}
output "routes" { value = { north = module.north.route, south = module.south.route } }
DQ_ASSET
cat > branches.tf <<'DQ_ASSET'
module "east" {
 source = "./modules/station"
 name = "east"
 upstream = local.hub
}
module "archive" {
 source = "./modules/station"
 name = "archive"
 upstream = "${module.south.route}|${module.east.route}"
}
DQ_ASSET
tofu fmt main.tf branches.tf delivery.tf
tofu fmt -check main.tf branches.tf delivery.tf
tofu init -input=false -no-color
tofu validate -no-color
tofu plan -input=false -no-color -out=acyclic.plan
tofu apply -input=false -no-color acyclic.plan
