set -euo pipefail
cd ~/quest
python3 - <<'ROUTE_VALUE'
from pathlib import Path
p=Path('main.tf');p.write_text(p.read_text().replace('content = "${each.key}', 'content = "${each.value}'))
ROUTE_VALUE
cat > terraform.tfvars <<'DQ_ASSET'
routes = { north = "open", south = "held", east = "open" }
DQ_ASSET
tofu apply -auto-approve -input=false -no-color
tofu fmt -recursive
tofu validate
