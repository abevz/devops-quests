set -euo pipefail
cd ~/quest
cat > chart/templates/bundle.yaml <<'DQ_BUNDLE'
apiVersion: v1
kind: ConfigMap
metadata:
  name: board-data
data:
  index.html: {{ printf "%s\n" (required "routeMessage is required" .Values.routeMessage) | quote }}
  release.json: {{ dict "release_id" .Values.releaseId "route" .Values.routeMessage | toJson | quote }}
DQ_BUNDLE
cat > chart/templates/service.yaml <<'DQ_SERVICE'
apiVersion: v1
kind: Service
metadata:
  name: board
spec:
  selector:
    app: board
  ports:
  - port: 8080
    targetPort: http
DQ_SERVICE
helm lint ./chart
helm upgrade board ./chart --reset-values -f chart/values.yaml --wait --timeout=90s
for attempt in $(seq 1 60); do
 if kubectl exec deployment/board -c worker -- wget -qO- -T 3 http://board:8080/release.json | jq -e --arg id "$(jq -r .release_id /run/dq/facts/0/helm-identities.json)" '.release_id==$id and .route=="north-67"' >/dev/null; then break; fi
 sleep .5
done
kubectl exec deployment/board -c worker -- wget -qO- -T 3 http://board:8080/release.json | jq -e --arg id "$(jq -r .release_id /run/dq/facts/0/helm-identities.json)" '.release_id==$id and .route=="north-67"' >/dev/null
