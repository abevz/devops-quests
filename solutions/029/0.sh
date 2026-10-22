set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
resource "local_file" "notice" {
 filename = "${path.root}/notice.txt"
 lifecycle { prevent_destroy = true }
 content = "north-ready\n"
}
DQ_ASSET
tofu apply -auto-approve -input=false -no-color
