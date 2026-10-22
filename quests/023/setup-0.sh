set -euo pipefail
mkdir -p modules/notice
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
module "stations" {
 source = "./modules/notice"
 for_each = toset(["north"])
 station = "retired"
}
output "messages" { value = {for key, station in module.stations : key => station.message} }
DQ_ASSET
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
