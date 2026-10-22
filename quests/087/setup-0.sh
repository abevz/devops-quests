set -euo pipefail
cat > main.tf <<'DQ_ASSET'
terraform {
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
 }
}
resource "local_file" "notice" {
 filename = "${path.root}/notice.txt"
 content = "north-ready\n"
}
DQ_ASSET
tofu init -input=false -no-color
tofu apply -auto-approve -input=false -no-color
cat > hold-state.py <<'PYHOLDER'
import os
import signal
import subprocess
from pathlib import Path

with open('/tmp/rail-lock.log', 'w') as output:
    process = subprocess.Popen(['tofu', 'console', '-no-color'], stdin=subprocess.PIPE,
                               stdout=output, stderr=output)
    signal.signal(signal.SIGTERM, lambda *_: process.stdin.close())
    Path('lock-holder.pid').write_text(str(os.getpid()))
    process.wait()
PYHOLDER
python3 hold-state.py >/tmp/rail-holder.log 2>&1 &
for _ in $(seq 1 50); do
  test -s .terraform.tfstate.lock.info && break
  sleep .1
done
test -s .terraform.tfstate.lock.info
if tofu plan -lock-timeout=1s -input=false -no-color > lock-probe.log 2>&1; then echo 'Expected a held lock' >&2; exit 1; fi
grep -q 'state lock' lock-probe.log
