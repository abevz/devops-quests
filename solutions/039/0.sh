set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
variable "departures" {
 type = number
 validation {
  condition = var.departures >= 1 && var.departures <= 6 && floor(var.departures) == var.departures
  error_message = "departures must be an integer from 1 to 6."
 }
}
resource "local_file" "timetable" {
 filename = "${path.root}/timetable.txt"
 content = "${var.departures}\n"
}
output "departures" { value = var.departures }
DQ_ASSET
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
