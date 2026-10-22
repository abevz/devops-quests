set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
locals {
 region = "north"
 stations = toset(["depot", "junction"])
}
module "station" {
 source = "./modules/station"
 for_each = local.stations
 station = each.key
 region = local.region
}
output "routes" { value = { for k,v in module.station : k => v.path } }
DQ_ASSET
tofu init -input=false -no-color
tofu plan -input=false -no-color -out=fanout.plan
tofu show -json fanout.plan > fanout-plan.json
tofu apply -input=false -no-color fanout.plan
