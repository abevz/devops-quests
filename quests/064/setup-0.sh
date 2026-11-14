set -euo pipefail
cd ~/quest
mkdir -p modules/station/modules/notice
cat > modules/station/modules/notice/main.tf <<'DQ_ASSET'
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
mkdir -p modules/station
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
 region = "retired"
}
output "routes" { value = { for k,v in module.station : k => v.path } }
DQ_ASSET
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
tofu state list | sed -n '/\.local_file\.route$/p' > original-addresses
tofu show -json > initial-state.json
python3 - <<'IDENTITIES'
import json
from pathlib import Path
from dq_check import resource_records
rows=resource_records(json.loads(Path('initial-state.json').read_text()))
identities={r['address']:r['values']['id'] for _,r in rows if r['type']=='terraform_data'}
assert len(identities)==2
Path('station-identities.json').write_text(json.dumps(identities,indent=2)+'\n')
IDENTITIES
rm initial-state.json
mkdir -p modules/station
cat > modules/station/main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
variable "station" { type = string }
resource "terraform_data" "identity" { input = var.station }
output "path" { value = module.notice.path }
output "id" { value = module.notice.id }
DQ_ASSET
cat > region-cases.json <<'DQ_ASSET'
{
  "variable": "region",
  "values": [
    "north",
    "west"
  ],
  "stations": [
    "depot",
    "junction"
  ]
}
DQ_ASSET
