set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
module "station" {
 source = "./modules/v2"
 name = "north"
}
module "depot" {
 source = "./modules/v1"
 name = "depot"
}
output "contracts" {
 value = {
  station = { release = module.station.release, checksum = try(module.station.checksum, "not-supported") }
  depot = { release = module.depot.release }
 }
}
output "ids" { value = { station = module.station.id, depot = module.depot.id } }
DQ_ASSET
tofu init -input=false -no-color
tofu plan -input=false -no-color -out=upgrade.plan
tofu show -json upgrade.plan > upgrade-plan.json
tofu apply -input=false -no-color upgrade.plan
