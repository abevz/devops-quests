set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
variable "replicas" {
 type = number
 validation {
  condition = var.replicas >= 1 && var.replicas <= 3 && floor(var.replicas) == var.replicas
  error_message = "Use an integer from 1 to 3."
 }
}
resource "local_file" "notice" {
 filename = "${path.root}/replicas.txt"
 content = tostring(var.replicas)
}
output "replicas" { value = var.replicas }
DQ_ASSET
cat > terraform.tfvars <<'DQ_ASSET'
replicas = 2
DQ_ASSET
tofu apply -auto-approve -input=false -no-color
