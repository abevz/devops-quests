set -euo pipefail
cd ~/quest
source platform.env
kubectl create secret docker-registry parcel-pull --docker-server="$REGISTRY" --docker-username="$REGISTRY_USER" --docker-password="$REGISTRY_PASSWORD"
cat > patch-204d465f5d54.json <<'DQ_ASSET'
{
  "spec": {
    "template": {
      "spec": {
        "imagePullSecrets": [
          {
            "name": "parcel-pull"
          }
        ]
      }
    }
  }
}
DQ_ASSET
jq -e . patch-204d465f5d54.json >/dev/null
kubectl patch deployment relay --type=merge --patch-file=patch-204d465f5d54.json
kubectl rollout status deployment/relay --timeout=90s
