set -euo pipefail
cd ~/quest
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
resource "local_file" "release" {
 filename = "${path.root}/release.txt"
 content = "release-90\n"
}
output "release" { value = local_file.release.content }
resource "terraform_data" "release_record" {
  input = trimspace(local_file.release.content)
}
variable "handover_status" {
  type    = string
  default = "at-checkpoint"
}
resource "terraform_data" "handover" {
  triggers_replace = var.handover_status
}
output "recovery_id" { value = terraform_data.release_record.id }
DQ_ASSET
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
mkdir -p recovery
cp terraform.tfstate recovery/checkpoint.tfstate
(cd recovery && sha256sum checkpoint.tfstate > checkpoint.sha256)
checkpoint_id=$(tofu output -raw recovery_id)
printf '%s\n' '{"handover_status":"after-checkpoint"}' > incident.auto.tfvars.json
tofu apply -auto-approve -input=false -no-color
handover_id=$(jq -er '.resources[] | select(.type=="terraform_data" and .name=="handover") | .instances[0].attributes.id' terraform.tfstate)
lineage=$(jq -er .lineage terraform.tfstate)
jq -n --arg release_id "$checkpoint_id" --arg handover_id "$handover_id" --arg lineage "$lineage" \
  --arg sha256 "$(cut -d ' ' -f 1 recovery/checkpoint.sha256)" \
  '{release_id:$release_id,handover_id:$handover_id,lineage:$lineage,sha256:$sha256}' > recovery-contract.json
tofu state rm local_file.release terraform_data.release_record
rm -f -- terraform.tfstate.backup release.txt
