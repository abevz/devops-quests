set -euo pipefail
cd ~/quest
cat > modules/notice/main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
variable "station" { type = string }
resource "local_file" "notice" {
 filename = "${path.root}/${var.station}.txt"
 content = "${var.station}-ready\n"
}
output "message" { value = local_file.notice.content }
DQ_ASSET
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
module "notice" {
 source = "./modules/notice"
 station = "north"
}
output "message" { value = module.notice.message }
DQ_ASSET
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
