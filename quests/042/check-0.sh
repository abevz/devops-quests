set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
source platform.env
board=$(kubectl get deployment board -o json 2>/dev/null || true)
if ! jq -e --arg image "$PRIVATE_IMAGE" '.spec.template.spec.containers[0].image==$image' <<<"$board" >/dev/null 2>&1; then printf '%s\n' 'deployment/board first image = PRIVATE_IMAGE: ✗ [DQ:image]'; failed=1; fi
check 'deployment/board replicas = 1 [DQ:replicas]' '.spec.replicas==1' "$board"
check 'deployment/board imagePullSecrets = [registry-pull] [DQ:secrets]' '.spec.template.spec.imagePullSecrets==[{name:"registry-pull"}]' "$board"
check 'deployment/board imagePullPolicy = Always [DQ:policy]' '.spec.template.spec.containers[0].imagePullPolicy=="Always"' "$board"
secret=$(kubectl get secret registry-pull -o json 2>/dev/null || true)
check 'registry-pull type = kubernetes.io/dockerconfigjson [DQ:secret_type]' '.type=="kubernetes.io/dockerconfigjson"' "$secret"
if ! printf '%s' "$secret" | python3 -c 'import base64,json,sys; data=json.load(sys.stdin)["data"][".dockerconfigjson"]; decoded=base64.b64decode(data,validate=True); assert base64.b64encode(decoded).decode()==data' >/dev/null 2>&1; then printf '%s\n' 'registry-pull dockerconfigjson = canonical base64: ✗ [DQ:outer]'; failed=1; fi
if ! printf '%s' "$secret" | python3 -c 'import base64,json,os,sys; outer=json.load(sys.stdin)["data"][".dockerconfigjson"]; data=json.loads(base64.b64decode(outer,validate=True)); auth=data["auths"][os.environ["REGISTRY"]]["auth"]; decoded=base64.b64decode(auth,validate=True); assert base64.b64encode(decoded).decode()==auth' >/dev/null 2>&1; then printf '%s\n' 'registry-pull auth = canonical base64: ✗ [DQ:auth]'; failed=1; fi
if ! printf '%s' "$secret" | python3 -c 'import base64,json,os,sys; outer=json.load(sys.stdin)["data"][".dockerconfigjson"]; data=json.loads(base64.b64decode(outer,validate=True)); auth=data["auths"][os.environ["REGISTRY"]]["auth"]; assert base64.b64decode(auth,validate=True).decode()==os.environ["REGISTRY_USER"]+":"+os.environ["REGISTRY_PASSWORD"]' >/dev/null 2>&1; then printf '%s\n' 'registry-pull auth matches platform.env: ✗ [DQ:credentials]'; failed=1; fi
if ! kubectl rollout status deployment/board --timeout=3s >/dev/null 2>&1; then printf '%s\n' 'deployment/board rollout complete: ✗ [DQ:rollout]'; failed=1; fi
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -- wget -qO- -T 3 http://127.0.0.1:8080 2>/dev/null)" = north-42; then printf '%s\n' 'board Pod localhost:8080 = north-42: ✗ [DQ:http]'; failed=1; fi
exit "$failed"
