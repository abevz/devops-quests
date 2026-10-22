set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
resource "local_file" "ledger" {
 filename = "${path.root}/ledger.txt"
 content = "revision-36\n"
}
output "ledger_id" { value = local_file.ledger.id }
DQ_ASSET
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
tofu output -raw ledger_id > original-id
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
resource "local_file" "ledger" {
 filename = "${path.root}/retired-ledger.txt"
 content = "revision-36\n"
}
output "ledger_id" { value = local_file.ledger.id }
DQ_ASSET
tofu init -input=false -no-color
