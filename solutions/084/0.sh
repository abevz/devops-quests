set -euo pipefail
cd ~/quest
tofu state pull > before-refactor.tfstate
mkdir -p modules/station
cat > modules/station/main.tf <<'DQ_MODULE'
terraform {
 required_providers {
  docker = { source = "registry.terraform.io/kreuzwerker/docker", version = "3.6.2" }
 }
}
resource "docker_container" "worker" {
 name = "rail-worker"
 image = "docker.io/library/busybox:1.37.0@sha256:66a6306db78bf2dbf3487f293aa8d6990d8e506fdffab9cc43fe422becf886e4"
 command = ["sleep", "36000"]
}
output "worker_id" { value = docker_container.worker.id }
DQ_MODULE
mkdir -p modules/fabric
cat > modules/fabric/main.tf <<'DQ_MODULE'
terraform {
 required_providers {
  docker = { source = "registry.terraform.io/kreuzwerker/docker", version = "3.6.2" }
 }
}
resource "docker_network" "backplane" { name = "rail-fabric" }
output "network" { value = docker_network.backplane.name }
DQ_MODULE
mkdir -p modules/route
cat > modules/route/main.tf <<'DQ_MODULE'
terraform {
 required_providers {
  docker = { source = "registry.terraform.io/kreuzwerker/docker", version = "3.6.2" }
 }
}
variable "route" { type = string }
variable "network" { type = string }
resource "docker_volume" "ledger" { name = "rail-${var.route}-data" }
resource "docker_container" "worker" {
 name = "rail-${var.route}"
 image = "docker.io/library/busybox:1.37.0@sha256:66a6306db78bf2dbf3487f293aa8d6990d8e506fdffab9cc43fe422becf886e4"
 command = ["sh", "-c", "test -s /data/ledger || printf '%s\\n' '${var.route}-retained' > /data/ledger; exec httpd -f -p 8080 -h /data"]
 networks_advanced { name = var.network }
 volumes {
  volume_name = docker_volume.ledger.id
  container_path = "/data"
 }
}
output "id" { value = docker_container.worker.id }
DQ_MODULE
cat > main.tf <<'DQ_ROOT'
terraform {
 required_providers {
  docker = { source = "registry.terraform.io/kreuzwerker/docker", version = "3.6.2" }
 }
}
provider "docker" {}
module "station" { source = "./modules/station" }
module "fabric" { source = "./modules/fabric" }
module "route" {
 for_each = toset(["north", "south"])
 source = "./modules/route"
 route = each.key
 network = module.fabric.network
}
output "worker_id" { value = module.station.worker_id }
output "routes" { value = { for key, item in module.route : key => item.id } }
moved {
 from = docker_container.worker
 to = module.station.docker_container.worker
}
moved {
 from = docker_network.backplane
 to = module.fabric.docker_network.backplane
}
moved {
 from = docker_volume.ledger[0]
 to = module.route["south"].docker_volume.ledger
}
moved {
 from = docker_container.node[0]
 to = module.route["south"].docker_container.worker
}
moved {
 from = docker_volume.ledger[1]
 to = module.route["north"].docker_volume.ledger
}
moved {
 from = docker_container.node[1]
 to = module.route["north"].docker_container.worker
}
DQ_ROOT
tofu fmt -recursive
tofu init -input=false -no-color
tofu validate -no-color
tofu plan -input=false -no-color -out=migration.plan
tofu show -json migration.plan > migration-plan.json
tofu apply -input=false -no-color migration.plan
