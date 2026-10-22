set -euo pipefail
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  docker = { source = "registry.terraform.io/kreuzwerker/docker", version = "3.6.2" }
 }
}
provider "docker" {}
resource "docker_container" "worker" {
 name = "rail-worker"
 image = "docker.io/library/busybox:1.37.0@sha256:66a6306db78bf2dbf3487f293aa8d6990d8e506fdffab9cc43fe422becf886e4"
 command = ["sleep", "36000"]
}
DQ_ASSET
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
docker inspect rail-worker --format '{{.Id}}' > original-id
mkdir -p modules/station
