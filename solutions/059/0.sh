set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
  required_providers {
    local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
  }
}
resource "terraform_data" "ledger" { input = { message = "north-ready" } }
resource "local_file" "ledger" {
  filename = "${path.root}/notice.txt"
  content = "${terraform_data.ledger.output.message}\n"
}
moved {
  from = local_file.notice
  to = local_file.ledger
}
moved {
  from = terraform_data.notice
  to = terraform_data.ledger
}
DQ_ASSET
tofu apply -auto-approve -input=false -no-color
tofu fmt -recursive
tofu validate
