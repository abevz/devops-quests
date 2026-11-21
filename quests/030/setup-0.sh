set -euo pipefail
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
resource "local_file" "release" {
 filename = "${path.root}/release.txt"
 content = "retired\n"
}
output "release" { value = local_file.release.content }
DQ_ASSET
printf '%s\n' release-30 > approved-release.txt
tofu init -input=false -no-color
