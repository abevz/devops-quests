set -euo pipefail
cd ~/quest
kill "$(cat lock-holder.pid)"
sleep 1
tofu plan -input=false -detailed-exitcode -no-color >/dev/null