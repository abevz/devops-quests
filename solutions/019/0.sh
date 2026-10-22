set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
resource "terraform_data" "directory" {
 provisioner "local-exec" { command = "sh prepare.sh" }
}
resource "terraform_data" "marker" {
 depends_on = [terraform_data.directory]
 provisioner "local-exec" { command = "sh write.sh" }
}
DQ_ASSET
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
