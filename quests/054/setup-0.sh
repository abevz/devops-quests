set -euo pipefail
source platform.env
mkdir -p repository/manifests
cat > repository/manifests/relay.json <<'DQ_ASSET'
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "relay"
  },
  "spec": {
    "replicas": 1,
    "selector": {
      "matchLabels": {
        "app": "relay"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "relay"
        }
      },
      "spec": {
        "securityContext": {
          "runAsNonRoot": true,
          "runAsUser": 1000,
          "seccompProfile": {
            "type": "RuntimeDefault"
          }
        },
        "containers": [
          {
            "name": "worker",
            "image": "${DQ_APP_IMAGE}",
            "imagePullPolicy": "Never",
            "command": [
              "sh",
              "-c",
              "mkdir -p /tmp/www; echo signalrail >/tmp/www/index.html; httpd -f -p 8080 -h /tmp/www"
            ],
            "ports": [
              {
                "containerPort": 8080
              }
            ],
            "resources": {
              "requests": {
                "cpu": "10m",
                "memory": "16Mi"
              },
              "limits": {
                "memory": "64Mi"
              }
            },
            "securityContext": {
              "allowPrivilegeEscalation": false,
              "capabilities": {
                "drop": [
                  "ALL"
                ]
              }
            },
            "env": [
              {
                "name": "ROUTE",
                "value": "north"
              }
            ]
          }
        ]
      }
    }
  }
}
DQ_ASSET
sed -i 's|${DQ_APP_IMAGE}|'"$DQ_APP_IMAGE"'|g' repository/manifests/relay.json
cd repository
git add manifests
git commit -m "Add station reader"
git remote add origin "$GIT_URL"
git push -u origin main
cd ..
cat > application.json <<'DQ_ASSET'
{
  "apiVersion": "argoproj.io/v1alpha1",
  "kind": "Application",
  "metadata": {
    "name": "station"
  },
  "spec": {
    "project": "station",
    "source": {
      "repoURL": "DQ_GIT_URL",
      "targetRevision": "main",
      "path": "manifests"
    },
    "destination": {
      "server": "https://kubernetes.default.svc",
      "namespace": "DQ_TARGET_NS"
    }
  }
}
DQ_ASSET
sed -i "s|DQ_GIT_URL|$GIT_URL|g; s|DQ_TARGET_NS|$DQ_NAMESPACE|g" application.json
kubectl apply -f application.json
cat > patch-4cf3f622c706.json <<'DQ_ASSET'
{
  "operation": {
    "sync": {}
  }
}
DQ_ASSET
jq -e . patch-4cf3f622c706.json >/dev/null
kubectl patch application station --type=merge --patch-file=patch-4cf3f622c706.json
for _ in $(seq 1 90); do
 if kubectl get application station -o json | jq -e '.status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null; then break; fi
 sleep 2
done
kubectl get application station -o json | jq -e '.status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null

kubectl set env deployment/relay ROUTE=drifted
kubectl rollout status deployment/relay --timeout=90s
kubectl annotate application station argocd.argoproj.io/refresh=hard --overwrite
kubectl wait --for=jsonpath='{.status.sync.status}'=OutOfSync application/station --timeout=60s
