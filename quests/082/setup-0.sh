set -euo pipefail
mkdir -p chart/templates
cat > chart/Chart.yaml <<'DQ_ASSET'
apiVersion: v2
name: station-board
version: 0.1.0
DQ_ASSET
cat > chart/templates/deploy.yaml <<'DQ_ASSET'
{"apiVersion": "apps/v1", "kind": "Deployment", "metadata": {"name": "relay"}, "spec": {"replicas": 1, "selector": {"matchLabels": {"app": "relay"}}, "template": {"metadata": {"labels": {"app": "relay"}}, "spec": {"securityContext": {"runAsNonRoot": true, "runAsUser": 1000, "seccompProfile": {"type": "RuntimeDefault"}}, "containers": [{"name": "worker", "image": "{{ .Values.image }}", "imagePullPolicy": "Never", "command": ["sh", "-c", "mkdir -p /tmp/www; echo signalrail >/tmp/www/index.html; httpd -f -p {{ .Values.port }} -h /tmp/www"], "ports": [{"containerPort": 8080}], "resources": {"requests": {"cpu": "10m", "memory": "16Mi"}, "limits": {"memory": "64Mi"}}, "securityContext": {"allowPrivilegeEscalation": false, "capabilities": {"drop": ["ALL"]}}}]}}}}
DQ_ASSET
cat > chart/values.yaml <<'DQ_ASSET'
image: docker.io/library/busybox:1.37.0@sha256:66a6306db78bf2dbf3487f293aa8d6990d8e506fdffab9cc43fe422becf886e4
port: bad-port
DQ_ASSET
helm install board ./chart
