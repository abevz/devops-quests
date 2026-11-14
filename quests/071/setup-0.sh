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
resource "terraform_data" "guardian" { input = "north-71" }
DQ_ASSET
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
tofu output -raw north_id > original-north-id
tofu state pull > recovery-checkpoint.tfstate
cat >> main.tf <<'DQ_ASSET'
resource "terraform_data" "progress" { input = "checkpoint-71" }
DQ_ASSET
tofu apply -target=terraform_data.progress -auto-approve -input=false -no-color
tofu state rm terraform_data.guardian
tofu state pull > partial-state.json
python3 - <<'IDENTITIES'
import hashlib,json
from pathlib import Path
def ids(document):
 return {r['type']+'.'+r['name']:r['instances'][0]['attributes']['id'] for r in document['resources'] if r.get('mode')=='managed'}
checkpoint=Path('recovery-checkpoint.tfstate');old=json.loads(checkpoint.read_text());current=json.loads(Path('partial-state.json').read_text())
old_ids=ids(old);current_ids=ids(current)
facts={'bindings':{'terraform_data.guardian':old_ids['terraform_data.guardian'],'terraform_data.progress':current_ids['terraform_data.progress']},'checkpoint_sha256':hashlib.sha256(checkpoint.read_bytes()).hexdigest(),'partial':{'lineage':current['lineage'],'serial':current['serial'],'identities':current_ids}}
Path('state-identities.json').write_text(json.dumps(facts,indent=2)+'\n')
IDENTITIES
rm partial-state.json
cat >> main.tf <<'DQ_ASSET'
resource "local_file" "south" {
 filename = "${path.root}/south.txt"
 content = "south-71\n"
}
DQ_ASSET
