set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
variable "departures" { type = number }
resource "local_file" "timetable" {
 filename = "${path.root}/timetable.txt"
 content = "${var.departures}\n"
}
output "departures" { value = var.departures }
DQ_ASSET
tofu init -input=false -no-color
cat > terraform.tfvars <<'DQ_ASSET'
departures = 3
DQ_ASSET
