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
tofu init -input=false -no-color
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
 upstream = module.south.route
}
module "south" {
 source = "./modules/station"
 name = "south"
 upstream = module.north.route
}
output "routes" { value = { north = module.north.route, south = module.south.route } }
DQ_ASSET
cat > delivery.tf <<'DQ_ASSET'
output "delivery_routes" {
 value = { east = module.east.route, archive = module.archive.route }
}
DQ_ASSET
cat > route-cases.json <<'DQ_ASSET'
{
  "variable": "hub",
  "cases": [
    {
      "input": "dispatch",
      "files": {
        "north.txt": "dispatch:north",
        "south.txt": "dispatch:north:south",
        "east.txt": "dispatch:east",
        "archive.txt": "dispatch:north:south|dispatch:east:archive"
      }
    },
    {
      "input": "relay",
      "files": {
        "north.txt": "relay:north",
        "south.txt": "relay:north:south",
        "east.txt": "relay:east",
        "archive.txt": "relay:north:south|relay:east:archive"
      }
    }
  ],
  "dependencies": {
    "south.txt": [
      "north.txt"
    ],
    "archive.txt": [
      "south.txt",
      "east.txt"
    ]
  }
}
DQ_ASSET
sha256sum modules/station/main.tf > original-module.sha256
