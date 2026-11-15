set -euo pipefail
cd ~/quest
handle=$(curl -fsS http://127.0.0.1:18787/owner | jq -r .handle)
curl -fsS -H 'Content-Type: application/json' -d "{\"handle\":\"$handle\"}" http://127.0.0.1:18787/owner/finish
for attempt in $(seq 1 100); do
  curl -fsS http://127.0.0.1:18787/owner | jq -e '.completed == true' >/dev/null && break
  sleep .1
done
curl -fsS http://127.0.0.1:18787/owner | jq -e '.completed == true' >/dev/null
if ! test -e before-recovery.tfstate; then
  tofu state pull > before-recovery.tfstate
fi
scratch=$(mktemp -d)
tofu state pull > "$scratch/current.tfstate"
cp errored.tfstate "$scratch/source.tfstate"
tofu -chdir="$scratch" state mv -state=source.tfstate -state-out=current.tfstate docker_container.operation docker_container.operation
tofu state push "$scratch/current.tfstate"
tofu plan -input=false -detailed-exitcode -no-color
