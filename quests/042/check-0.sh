set -euo pipefail
cd ~/quest
source platform.env
kubectl get deployment board -o json | jq -e --arg image "$PRIVATE_IMAGE" ' .spec.template.spec.containers[0].image==$image and .spec.replicas==1' >/dev/null
kubectl get deployment board -o json | jq -e '.spec.template.spec.imagePullSecrets==[{"name":"registry-pull"}] and .spec.template.spec.containers[0].imagePullPolicy=="Always"' >/dev/null
kubectl get secret registry-pull -o json | python3 -c 'import base64,json,os,sys; s=json.load(sys.stdin); d=json.loads(base64.b64decode(s["data"][".dockerconfigjson"])); a=d["auths"][os.environ["REGISTRY"]]; assert base64.b64decode(a["auth"]).decode()==os.environ["REGISTRY_USER"]+":"+os.environ["REGISTRY_PASSWORD"]'
kubectl rollout status deployment/board --timeout=3s >/dev/null
test "$(kubectl exec deployment/board -- wget -qO- http://127.0.0.1:8080)" = north-42
