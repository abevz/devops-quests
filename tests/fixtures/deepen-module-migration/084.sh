set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  docker = { source = "registry.terraform.io/kreuzwerker/docker", version = "3.6.2" }
 }
}
provider "docker" {}
module "station" {
 source = "./modules/station"
 image = "docker.io/library/busybox:1.37.0@sha256:66a6306db78bf2dbf3487f293aa8d6990d8e506fdffab9cc43fe422becf886e4"
}
moved {
 from = docker_container.worker
 to = module.station.docker_container.worker
}
output "worker_id" { value = module.station.worker_id }
DQ_ASSET
cat > modules/station/main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  docker = { source = "registry.terraform.io/kreuzwerker/docker", version = "3.6.2" }
 }
}

variable "image" { type = string }
resource "docker_container" "worker" {
 name = "rail-worker"
 image = var.image
 command = ["sleep", "36000"]
}
output "worker_id" { value = docker_container.worker.id }
DQ_ASSET
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
