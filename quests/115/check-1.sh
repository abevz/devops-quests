set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
set -euo pipefail
cd ~/quest
failed=0
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
deployments=$(timeout 2s kubectl get deployment blue green -o json 2>/dev/null || true)
check blue_replicas 'blue replicas = 3' 'any(.items[]?;.metadata.name=="blue" and .spec.replicas==3)' "$deployments"
check blue_ready 'blue readyReplicas = 3' 'any(.items[]?;.metadata.name=="blue" and .status.readyReplicas==3)' "$deployments"
check green_replicas 'green replicas = 1' 'any(.items[]?;.metadata.name=="green" and .spec.replicas==1)' "$deployments"
check green_ready 'green readyReplicas = 1' 'any(.items[]?;.metadata.name=="green" and .status.readyReplicas==1)' "$deployments"
exit "$failed"

)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
deployments=$(timeout 2s kubectl get deployment blue green -o json 2>/dev/null || true)
service=$(timeout 2s kubectl get service board -o json 2>/dev/null || true)
endpoints=$(timeout 2s kubectl get endpointslices -l kubernetes.io/service-name=board -o json 2>/dev/null || true)
check selector_canary 'service/board selector = release board' '.spec.selector=={release:"board"}' "$service"
check endpoints 'four unique ready EndpointSlice target names' '[.items[].endpoints[] | select(.conditions.ready==true and (.targetRef.name | type=="string" and length>0)) | .targetRef.name] | unique | length==4' "$endpoints"
exit "$failed"

)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
python3 - <<'DQ_PROBES'
import concurrent.futures
import subprocess
import sys
import time

# Includes both Kubernetes lookups. Reserve 3s for the Service and 0.5s for diagnostics.
deadline = time.monotonic() + 22
pod_deadline = deadline - 3.5
failed = False
pod_markers = {"blue": "[DQ:pod_blue]", "green": "[DQ:pod_green]"}
ip_markers = {"blue": "[DQ:ips_blue]", "green": "[DQ:ips_green]"}

def output(arguments):
    return subprocess.run(arguments, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          check=False).stdout.replace(b"\x00", b"").rstrip(b"\n")

def probe(target):
    version, ip = target
    actual = output(["timeout", "3s", "kubectl", "exec", "--pod-running-timeout=2s",
                     "deployment/client", "--", "wget", "-qO-", "-T", "2", f"http://{ip}:8080"])
    return actual == f"{version}-115".encode()

targets = []
for version in ("blue", "green"):
    ips = output(["timeout", "2s", "kubectl", "get", "pods", "-l", f"app={version}",
                  "-o", "jsonpath={.items[*].status.podIP}"]).decode().split()
    if not ips:
        print(f"{version} Pod IPs present: ✗ {ip_markers[version]}", flush=True)
        failed = True
    targets.extend((version, ip) for ip in ips)

next_target = 0
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    active = {}
    while next_target < len(targets) or active:
        while len(active) < 2 and next_target < len(targets) and time.monotonic() + 3 <= pod_deadline:
            target = targets[next_target]
            active[pool.submit(probe, target)] = target
            next_target += 1
        if not active:
            break
        completed, _ = concurrent.futures.wait(active, return_when=concurrent.futures.FIRST_COMPLETED)
        for future in completed:
            version, ip = active.pop(future)
            if not future.result():
                print(f"{version} Pod {ip}:8080 = {version}-115: ✗ {pod_markers[version]}", flush=True)
                failed = True

if next_target < len(targets):
    pending = ", ".join(ip for _, ip in targets[next_target:])
    print(f"Probe time budget exhausted; unchecked Pod IPs: {pending}: ✗ [DQ:probe_budget]", flush=True)
    failed = True

actual = output(["timeout", "3s", "kubectl", "exec", "--pod-running-timeout=2s",
                 "deployment/client", "--", "wget", "-qO-", "-T", "2", "http://board:8080"])
if actual not in (b"blue-115", b"green-115"):
    print("board:8080 = blue-115 or green-115: ✗ [DQ:canary_http]", flush=True)
    failed = True
sys.exit(int(failed))
DQ_PROBES

)
[ $? -eq 0 ] || failed=1
exit "$failed"
