set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
module "stations" {
 source = "./modules/notice"
 for_each = toset(["north", "south"])
 station = each.key
}
output "messages" { value = {for key, station in module.stations : key => station.message} }
DQ_ASSET
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
