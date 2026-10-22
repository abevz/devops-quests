set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
locals { hub = "dispatch" }
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
tofu init -input=false -no-color
tofu validate -no-color
tofu plan -input=false -no-color -out=acyclic.plan
tofu apply -input=false -no-color acyclic.plan
