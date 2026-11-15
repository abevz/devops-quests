set -euo pipefail
cd ~/quest
audience=$(kubectl config view --raw --minify -o json | python3 -I -c '
import base64,json,sys
config=json.load(sys.stdin)
token=config["users"][0]["user"]["token"]
claims=json.loads(base64.urlsafe_b64decode(token.split(".")[1]+"==="))
audience=claims["aud"]
if isinstance(audience,list):
    audience=audience[0]
assert isinstance(audience,str) and audience
print(audience)
')
patch=$(jq -nc --arg audience "$audience" '[{"op":"replace","path":"/spec/template/spec/volumes/0/projected/sources/0/serviceAccountToken/audience","value":$audience}]')
kubectl patch deployment reader --type=json -p "$patch"
account=$(kubectl get deployment reader -o jsonpath='{.spec.template.spec.serviceAccountName}')
kubectl create rolebinding reader --role=reader --serviceaccount="$DQ_NAMESPACE:$account" --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout status deployment/reader --timeout=90s
