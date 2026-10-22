set -euo pipefail
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
resource "local_file" "notice" {
 filename = "${path.root}/notice.txt"
 content = "north-ready\n"
}
DQ_ASSET
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
mkdir -p modules/notice
cat > modules/notice/README.md <<'DQ_ASSET'
Build a local module with station input and message output. The north.txt file must contain north-ready. Do not use remote modules.
DQ_ASSET
