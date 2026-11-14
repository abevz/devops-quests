set -euo pipefail
cd ~/quest
python3 - <<'DQ_REPAIR'
from pathlib import Path
p=Path('main.tf');s=p.read_text();assert 'release = "retired"' in s;p.write_text(s.replace('release = "retired"','release = trimspace(local_file.release.content)'))
DQ_REPAIR
cat > modules/delivery/main.tf <<'DQ_MODULE'
variable "release" { type = string }
variable "producer_id" { type = string }
variable "targets" { type = set(string) }
output "contract" {
 value = {
  release = var.release
  producer_id = var.producer_id
  targets = { for target in var.targets : target => {
   target = target
   release = var.release
   producer_id = var.producer_id
  } }
 }
}
DQ_MODULE
tofu fmt -recursive
tofu validate -no-color
tofu plan -input=false -no-color -out=delivery.plan
tofu apply -input=false -no-color delivery.plan
