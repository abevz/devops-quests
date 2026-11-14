set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
  required_providers {
    local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
  }
}
resource "terraform_data" "notice" { input = { message = "north-ready" } }
resource "local_file" "notice" {
  filename = "${path.root}/notice.txt"
  content = "${terraform_data.notice.output.message}\n"
}
DQ_ASSET
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
tofu show -json | jq -er '.values.root_module.resources[] | select(.type=="local_file") | .values.id' > original-id
tofu show -json | jq -er '.values.root_module.resources[] | select(.type=="terraform_data") | .values.id' > original-identity
python3 - <<'ADDRESSES'
from pathlib import Path
p=Path('main.tf');p.write_text(p.read_text().replace('"notice"','"ledger"').replace('terraform_data.notice','terraform_data.ledger'))
ADDRESSES
