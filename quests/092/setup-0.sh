set -euo pipefail
cd ~/quest
mkdir -p modules/ledger
cat > modules/ledger/main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
variable "route" { type = string }
resource "local_file" "ledger" {
 filename = "${path.root}/ledger.txt"
 content = var.route
}
output "id" { value = local_file.ledger.id }
DQ_ASSET
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
module "north" {
 source = "./modules/ledger"
 route = "north-92\n"
}
output "ledger_id" { value = module.north.id }
DQ_ASSET
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
tofu state pull > safe-state.json
sha256sum safe-state.json | cut -d' ' -f1 > safe-state.sha256
tofu output -raw ledger_id > original-id
tofu state mv module.north module.orphan
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
module "station" {
 source = "./modules/ledger"
 route = "north-92\n"
}
output "ledger_id" { value = module.station.id }
DQ_ASSET
tofu init -input=false -no-color
