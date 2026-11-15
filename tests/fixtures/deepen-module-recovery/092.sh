set -euo pipefail
cd ~/quest
tofu state mv module.orphan module.station
tofu plan -input=false -no-color -out=recovery.plan
tofu show -json recovery.plan > recovery-plan.json
tofu apply -input=false -no-color recovery.plan
