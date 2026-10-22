set -euo pipefail
cd ~/quest
jq '.spec.template.spec.source.path="stations/{{.station}}"' applicationset.json > /tmp/appset.json
cp /tmp/appset.json applicationset.json
for i in $(seq 1 90); do
 if bash wait-apps.sh; then break; fi
 sleep 1
done
bash wait-apps.sh
