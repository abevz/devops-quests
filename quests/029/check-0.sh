set -euo pipefail
cd ~/quest
tofu state list | grep -Fx local_file.notice >/dev/null
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
if tofu plan -destroy -input=false -no-color > destroy-plan.log 2>&1; then exit 1; fi
grep -q prevent_destroy destroy-plan.log
test -s notice.txt
