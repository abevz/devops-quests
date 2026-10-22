set -euo pipefail
cd ~/quest
mkdir -p modules/station
cat > modules/station/main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
variable "name" { type = string }
variable "upstream" { type = string }
resource "local_file" "route" {
 filename = "${path.root}/${var.name}.txt"
 content = "${var.upstream}:${var.name}\n"
}
output "route" { value = trimspace(local_file.route.content) }
DQ_ASSET
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
 upstream = module.south.route
}
module "south" {
 source = "./modules/station"
 name = "south"
 upstream = module.north.route
}
output "routes" { value = { north = module.north.route, south = module.south.route } }
DQ_ASSET
sha256sum modules/station/main.tf > original-module.sha256
