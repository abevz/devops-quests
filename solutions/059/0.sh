set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
resource "local_file" "ledger" {
 filename = "${path.root}/notice.txt"
 content = "north-ready\n"
}
moved {
 from = local_file.notice
 to = local_file.ledger
}
DQ_ASSET
tofu apply -auto-approve -input=false -no-color
