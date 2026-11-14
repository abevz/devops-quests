set -euo pipefail
cd ~/quest
tofu state pull > before-recovery.tfstate
cp recovery-checkpoint.tfstate /tmp/recovery-working.tfstate
tofu state mv -state=/tmp/recovery-working.tfstate -state-out=terraform.tfstate terraform_data.guardian terraform_data.guardian
tofu fmt -check main.tf || tofu fmt main.tf
tofu validate -no-color
tofu plan -input=false -no-color -out=recovery.plan
tofu show -json recovery.plan > recovery-plan.json
tofu apply -input=false -no-color recovery.plan
