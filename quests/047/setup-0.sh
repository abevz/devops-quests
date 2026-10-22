set -euo pipefail
cd ~/quest
mkdir -p modules/v1
cat > modules/v1/main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
variable "name" { type = string }
resource "local_file" "notice" {
 filename = "${path.root}/${var.name}.txt"
 content = "${var.name}-47\n"
}
output "release" { value = 1 }
output "id" { value = local_file.notice.id }
DQ_ASSET
mkdir -p modules/v2
cat > modules/v2/main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
variable "name" { type = string }
resource "local_file" "notice" {
 filename = "${path.root}/${var.name}.txt"
 content = "${var.name}-47\n"
}
output "release" { value = 2 }
output "id" { value = local_file.notice.id }
output "checksum" { value = sha256(local_file.notice.content) }
DQ_ASSET
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
module "station" {
 source = "./modules/v1"
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
tofu apply -auto-approve -input=false -no-color
tofu state list > original-addresses
tofu output -json ids > original-ids.json
