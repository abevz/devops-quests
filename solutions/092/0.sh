set -euo pipefail
cd ~/quest
mkdir -p infra/modules/fabric
cat > infra/modules/fabric/main.tf <<'HCL'
terraform {
 required_providers {
  docker = { source = "registry.terraform.io/kreuzwerker/docker", version = "3.6.2" }
 }
}
variable "image" { type = string }
variable "network_name" { type = string }
variable "volume_name" { type = string }
variable "worker_name" { type = string }
resource "docker_network" "backplane" { name = var.network_name }
resource "docker_volume" "ledger" { name = var.volume_name }
resource "docker_container" "worker" {
 name = var.worker_name
 image = var.image
 command = ["sleep", "36000"]
 networks_advanced { name = docker_network.backplane.id }
 volumes {
  volume_name = docker_volume.ledger.name
  container_path = "/data"
 }
}
output "runtime" {
 value = {
  container_id = docker_container.worker.id
  network_id = docker_network.backplane.id
  volume_name = docker_volume.ledger.name
 }
}
HCL
tofu -chdir=infra init -input=false -no-color
tofu state pull > before-recovery.tfstate
tofu -chdir=infra state pull > infra/before-recovery.tfstate
scratch=$(mktemp -d)
cp safe-state.json "$scratch/source.tfstate"
cp infra/before-recovery.tfstate "$scratch/target.tfstate"
tofu -chdir="$scratch" state mv -state=source.tfstate -state-out=target.tfstate module.fabric module.fabric
tofu -chdir=infra state push "$scratch/target.tfstate"
tofu state mv module.orphan module.station
tofu plan -input=false -no-color -out=recovery.plan
tofu show -json recovery.plan > recovery-plan.json
tofu apply -input=false -no-color recovery.plan
tofu -chdir=infra plan -input=false -no-color -out=recovery.plan
tofu -chdir=infra show -json recovery.plan > infra/recovery-plan.json
tofu -chdir=infra apply -input=false -no-color recovery.plan
tofu plan -input=false -detailed-exitcode -no-color
tofu -chdir=infra plan -input=false -detailed-exitcode -no-color
