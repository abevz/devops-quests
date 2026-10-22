set -euo pipefail
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
resource "local_file" "release" {
 filename = "${path.root}/release.txt"
 content = "release-81\n"
}
output "release" { value = local_file.release.content }
DQ_ASSET
tofu init -input=false -no-color
