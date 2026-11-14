set -euo pipefail
cd ~/quest
mkdir -p modules/notice modules/dispatch
cat > main.tf <<'DQ_ASSET'
terraform {
  required_providers {
    local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
  }
}
variable "station" {
  description = "module-contract.json"
  type = string
}
module "notice" {
  source = "./modules/notice"
  station = var.station
}
module "dispatch" {
  source = "./modules/dispatch"
  message = module.notice.message
}
output "message" { value = module.dispatch.message }
DQ_ASSET
cat > terraform.tfvars <<'DQ_ASSET'
station = "north"
DQ_ASSET
cat > modules/notice/main.tf <<'DQ_ASSET'
terraform {
  required_providers {
    local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
  }
}
variable "station" {
  description = "module-contract.json"
  type = string
}
resource "local_file" "notice" {
  filename = "${path.root}/${var.station}.txt"
  content = "${var.station}-ready\n"
}
output "message" { value = local_file.notice.content }
DQ_ASSET
cat > modules/dispatch/main.tf <<'DQ_ASSET'
terraform {
  required_providers {
    local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
  }
}
variable "message" {
  description = "module-contract.json"
  type = string
}
resource "terraform_data" "receipt" { input = var.message }
resource "local_file" "receipt" {
  filename = "${path.root}/delivered.txt"
  content = var.message
}
output "message" { value = local_file.receipt.content }
DQ_ASSET
cat > module-contract.json <<'DQ_ASSET'
{
  "producer": {
    "input": {
      "station": "string"
    },
    "filename": "{station}.txt",
    "message": "{station}-ready"
  },
  "consumer": {
    "input": {
      "message": "string"
    },
    "filename": "delivered.txt"
  },
  "station_cases": [
    "north",
    "south"
  ]
}
DQ_ASSET
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
tofu show -json | jq -er '.values.root_module.child_modules[].resources[] | select(.type=="terraform_data") | .values.id' > original-consumer-id
cat > modules/notice/main.tf <<'DQ_ASSET'
terraform {
  required_providers {
    local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
  }
}
output "message" { value = local_file.absent.content }
DQ_ASSET
cat > modules/dispatch/main.tf <<'DQ_ASSET'
terraform {
  required_providers {
    local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
  }
}
variable "message" {
  description = "module-contract.json"
  type = number
}
resource "terraform_data" "receipt" { input = var.message }
resource "local_file" "receipt" {
  filename = "${path.root}/delivered.txt"
  content = var.message
}
output "notice" { value = local_file.receipt.content }
DQ_ASSET
