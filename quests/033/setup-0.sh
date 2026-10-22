set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
variable "routes" { type = map(string) }
resource "local_file" "route" {
 for_each = var.routes
 filename = "${path.root}/${each.key}.txt"
 content = "${each.value}\n"
}
output "routes" { value = { for k,v in local_file.route : k => v.id } }
DQ_ASSET
tofu init -input=false -no-color
cat > terraform.tfvars <<'DQ_ASSET'
routes = { north = "open", south = "held" }
DQ_ASSET
tofu apply -auto-approve -input=false -no-color
tofu output -json routes > original-ids.json
