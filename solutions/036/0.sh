set -euo pipefail
cd ~/quest
tofu plan -input=false -no-color -out=rejected.plan >/dev/null
tofu show -json rejected.plan > rejected-plan.json
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
