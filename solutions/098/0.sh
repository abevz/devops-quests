set -euo pipefail
cd ~/quest
python3 - <<'FIX'
from pathlib import Path
p=Path('modules/station/main.tf');p.write_text(p.read_text().replace('value = "retired-98"','value = trimspace(local_file.contract.content)'))
FIX
tofu plan -input=false -no-color -out=contract.plan
tofu apply -input=false -no-color contract.plan
tofu output -json contract > contract.json
ansible-playbook rollout.yml -e @contract.json
route=$(jq -er .route contract.json)
kubectl create configmap route --from-literal=route="$route" --dry-run=client -o json | kubectl apply -f -
kubectl rollout restart deployment/board
kubectl rollout status deployment/board --timeout=60s
