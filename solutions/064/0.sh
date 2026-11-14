set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
variable "region" {
 type = string
 default = "north"
}
locals {
 region = var.region
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
cat > modules/station/main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
variable "station" { type = string }
variable "region" { type = string }
module "notice" {
 source = "./modules/notice"
 station = var.station
 region = var.region
}
resource "terraform_data" "identity" { input = var.station }
output "path" { value = module.notice.path }
output "id" { value = module.notice.id }
DQ_ASSET
tofu fmt -recursive
tofu init -input=false -no-color
tofu validate -no-color
tofu plan -input=false -no-color -out=fanout.plan
tofu show -json fanout.plan > fanout-plan.json
tofu apply -input=false -no-color fanout.plan
