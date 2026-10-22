set -euo pipefail
cd ~/quest
mkdir -p modules/station
cat > modules/station/main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
variable "station" { type = string }
variable "region" { type = string }
resource "local_file" "route" {
 filename = "${path.root}/${var.station}.txt"
 content = "${var.region}:${var.station}\n"
}
output "path" { value = local_file.route.filename }
output "id" { value = local_file.route.id }
DQ_ASSET
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
 region = "retired"
}
output "routes" { value = { for k,v in module.station : k => v.path } }
DQ_ASSET
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
tofu state list > original-addresses
