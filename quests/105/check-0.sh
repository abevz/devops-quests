set -euo pipefail
cd ~/quest
kubectl get deployment station-dns -o json | jq -e '.spec.template.spec.containers[0].command==["/coredns","-conf","/etc/station/Corefile"]' >/dev/null
kubectl get service station-dns -o json | jq -e '[.spec.ports[] | [.port,.targetPort,.protocol]] | sort == [[53,1053,"TCP"],[53,1053,"UDP"]]' >/dev/null
kubectl get configmap station-dns -o jsonpath='{.data.Corefile}' > /tmp/dq-live-corefile
python3 - /tmp/dq-live-corefile /run/dq/facts/0/expected-dns-address <<'DQ_CORE'
import re,sys
from pathlib import Path
actual=re.sub(r'\s+',' ',Path(sys.argv[1]).read_text()).strip()
expected='.:1053 { errors hosts { '+Path(sys.argv[2]).read_text().strip()+' north.station.internal ttl 1 } }'
assert actual==expected, 'Keep the supplied DNS server port and one-second TTL'
DQ_CORE
dns_ip=$(kubectl get service station-dns -o jsonpath='{.spec.clusterIP}')
kubectl get deployment client -o json | jq -e --arg ip "$dns_ip" '.spec.template.spec.dnsPolicy=="None" and .spec.template.spec.dnsConfig.nameservers==[$ip]' >/dev/null
kubectl exec deployment/client -- nslookup north.station.internal "$dns_ip" | grep -F "$(cat /run/dq/facts/0/expected-dns-address)" >/dev/null
test "$(kubectl exec deployment/client -- wget -qO- -T 3 http://north.station.internal:8080)" = north-105
