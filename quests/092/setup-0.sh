set -euo pipefail
cd ~/quest
mkdir -p modules/ledger modules/fabric infra/modules
image=$(docker image inspect "$DQ_APP_IMAGE" --format '{{.Id}}')
printf %s "$image" > image-id
python3 - <<'HCL'
import json
from pathlib import Path
local='''terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
'''
both='''terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
  docker = { source = "registry.terraform.io/kreuzwerker/docker", version = "3.6.2" }
 }
}
provider "docker" {}
'''
Path('modules/ledger/main.tf').write_text(local+'''variable "route" { type = string }
resource "local_file" "ledger" {
 filename = "${path.root}/ledger.txt"
 content = var.route
}
output "id" { value = local_file.ledger.id }
''')
Path('modules/fabric/main.tf').write_text('''terraform {
 required_providers {
  docker = { source = "registry.terraform.io/kreuzwerker/docker", version = "3.6.2" }
 }
}
variable "image" { type = string }
variable "network_name" { type = string }
variable "volume_name" { type = string }
variable "worker_name" { type = string }
resource "docker_network" "backplane" { name = var.network_name }
resource "docker_volume" "ledger" { name = var.volume_name }
resource "docker_container" "worker" {
 name = var.worker_name
 image = var.image
 command = ["sleep", "36000"]
 networks_advanced { name = docker_network.backplane.id }
 volumes {
  volume_name = docker_volume.ledger.name
  container_path = "/data"
 }
}
output "runtime" {
 value = {
  container_id = docker_container.worker.id
  network_id = docker_network.backplane.id
  volume_name = docker_volume.ledger.name
 }
}
''')
inputs={'image':Path('image-id').read_text(),'network_name':'rail-ledger','volume_name':'rail-ledger-data','worker_name':'rail-ledger-worker'}
Path('infra/runtime-inputs.json').write_text(json.dumps(inputs,indent=2)+'\n')
contract={'inputs':{'image':'string','network_name':'string','volume_name':'string','worker_name':'string'},'outputs':{'runtime':{'container_id':'docker_container.id','network_id':'docker_network.id','volume_name':'docker_volume.name'}},'worker_storage':{'type':'volume','mount':'/data','retained_file':'/data/ledger'},'managed_inventory':{'main':{'local_file':1},'infra':{'docker_container':1,'docker_network':1,'docker_volume':1,'terraform_data':1}},'saved_plans':{'main':'recovery-plan.json','infra':'infra/recovery-plan.json'}}
Path('infra/module-contract.json').write_text(json.dumps(contract,indent=2)+'\n')
call='''module "fabric" {
 source = "./modules/fabric"
 image = local.inputs.image
 network_name = local.inputs.network_name
 volume_name = local.inputs.volume_name
 worker_name = local.inputs.worker_name
}
'''
Path('main.tf').write_text(both+'''locals { inputs = jsondecode(file("${path.module}/infra/runtime-inputs.json")) }
module "north" {
 source = "./modules/ledger"
 route = "north-92\\n"
}
output "ledger_id" { value = module.north.id }
'''+call)
Path('infra/main.tf').write_text(both+'''resource "terraform_data" "progress" { input = "split-completed-before-recovery" }
''')
HCL
tofu init -input=false -no-color
tofu apply -input=false -auto-approve -no-color
docker exec rail-ledger-worker sh -c 'printf "north-92\nsequence=000007\n" > /data/ledger'
tofu state pull > safe-state.json
sha256sum safe-state.json | cut -d' ' -f1 > safe-state.sha256
tofu output -raw ledger_id > original-id
tofu -chdir=infra init -input=false -no-color
tofu -chdir=infra apply -input=false -auto-approve -no-color
tofu state rm module.fabric
tofu state mv module.north module.orphan
python3 - <<'HCL'
from pathlib import Path
p=Path('main.tf');s=p.read_text();s=s[:s.index('module "fabric"')];s=s.replace('module "north"','module "station"').replace('module.north.id','module.station.id');p.write_text(s)
HCL
tofu init -input=false -no-color
tofu state pull > current-root.json
tofu -chdir=infra state pull > current-infra.json
python3 - <<'IDENTITIES'
from pathlib import Path
import json,subprocess,hashlib
old=json.loads(Path('safe-state.json').read_text());current=json.loads(Path('current-root.json').read_text());infra=json.loads(Path('current-infra.json').read_text())
objects={r['type']:r['instances'][0]['attributes']['id'] for r in old['resources']}
worker=json.loads(subprocess.run(['docker','inspect','rail-ledger-worker'],check=True,capture_output=True,text=True).stdout)[0]
volume=json.loads(subprocess.run(['docker','volume','inspect','rail-ledger-data'],check=True,capture_output=True,text=True).stdout)[0]
data=subprocess.run(['docker','exec','rail-ledger-worker','cat','/data/ledger'],check=True,capture_output=True).stdout
canonical=lambda v:hashlib.sha256(json.dumps(v,sort_keys=True,separators=(',',':')).encode()).hexdigest()
progress=infra['resources'][0]['instances'][0]['attributes']
facts={'progress_input':progress['input'],'progress_output':progress['output'],'container_id':objects['docker_container'],'network_id':objects['docker_network'],'volume_name':objects['docker_volume'],'volume_created_at':volume['CreatedAt'],'data_sha256':hashlib.sha256(data).hexdigest(),'progress_id':infra['resources'][0]['instances'][0]['attributes']['id'],'root_lineage':current['lineage'],'infra_lineage':infra['lineage'],'root_serial':current['serial'],'infra_serial':infra['serial'],'root_backup_sha256':canonical(current),'infra_backup_sha256':canonical(infra)}
Path('recovery-identities.json').write_text(json.dumps(facts,indent=2)+'\n')
# Complete only the caller. Its module package was lost during the split.
p=Path('infra/main.tf');p.write_text(p.read_text()+'''locals { inputs = jsondecode(file("${path.module}/runtime-inputs.json")) }
module "fabric" {
 source = "./modules/fabric"
 image = local.inputs.image
 network_name = local.inputs.network_name
 volume_name = local.inputs.volume_name
 worker_name = local.inputs.worker_name
}
output "runtime" { value = module.fabric.runtime }
''')
IDENTITIES
rm -r modules/fabric
rm image-id current-root.json current-infra.json
