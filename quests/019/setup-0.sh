set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
resource "terraform_data" "directory" {
 depends_on = [terraform_data.marker]
 provisioner "local-exec" { command = "sh prepare.sh" }
}
resource "terraform_data" "marker" {
 provisioner "local-exec" { command = "sh write.sh" }
}
DQ_ASSET
tofu init -input=false -no-color
cat > prepare.sh <<'DQ_ASSET'
set -eu
mkdir -p work
printf prepared > work/.prepared
DQ_ASSET
cat > write.sh <<'DQ_ASSET'
set -eu
test -f work/.prepared
printf "north\n" > work/route.txt
DQ_ASSET
