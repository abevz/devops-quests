set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
variable "station" { type = string }
variable "departures" { type = number }
resource "local_file" "notice" {
 filename = "${path.root}/notice.txt"
 content = "${var.station}:${var.departures}\n"
}
output "station" { value = var.station }
output "departures" { value = var.departures }
DQ_ASSET
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
