set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
  required_providers {
    local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
  }
}
variable "replicas" {
  description = "capacity-contract.json"
  type = number
  validation {
    condition = var.replicas >= 1 && var.replicas <= 3 && floor(var.replicas) == var.replicas && var.replicas <= length(var.pool.zones) * var.pool.slots_per_zone
    error_message = "capacity-contract.json"
  }
}
variable "pool" {
  description = "capacity-contract.json"
  type = object({ zones = list(string), slots_per_zone = number })
  validation {
    condition = length(var.pool.zones) > 0 && length(distinct(var.pool.zones)) == length(var.pool.zones) && var.pool.slots_per_zone >= 1 && floor(var.pool.slots_per_zone) == var.pool.slots_per_zone
    error_message = "capacity-contract.json"
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
pool = { zones = ["north", "south"], slots_per_zone = 1 }
DQ_ASSET
tofu apply -auto-approve -input=false -no-color
tofu fmt -recursive
tofu validate
