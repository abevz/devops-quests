set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
resource "local_file" "north" {
 filename = "${path.root}/north.txt"
 content = "north-71\n"
}
output "north_id" { value = local_file.north.id }
DQ_ASSET
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
tofu output -raw north_id > original-north-id
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
resource "local_file" "north" {
 filename = "${path.root}/north.txt"
 content = "north-71\n"
}
output "north_id" { value = local_file.north.id }
resource "local_file" "south" {
 filename = "${path.root}/south.txt"
 content = "south-71\n"
}
DQ_ASSET
tofu init -input=false -no-color
