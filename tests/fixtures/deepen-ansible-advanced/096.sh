set -euo pipefail
cd ~/quest
python3 - <<'FIX'
from pathlib import Path
p=Path('rollout.yml');p.write_text(p.read_text().replace('0'*64,Path('/run/dq/facts/0/artifact.sha256').read_text().strip()))
FIX
ansible-playbook rollout.yml
