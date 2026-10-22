set -euo pipefail
cd ~/quest
test "$(cat replicas.txt)" = 2
tofu plan -input=false -var=replicas=2 -detailed-exitcode >/dev/null
for bad in 0 4 1.5; do if tofu plan -input=false -var="replicas=$bad" >/dev/null 2>&1; then exit 1; fi; done
