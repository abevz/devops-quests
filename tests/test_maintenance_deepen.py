"""Pinned API behavior and authority boundaries for the broader 085 scenario."""

import json
import os
import secrets
import subprocess
from pathlib import Path

import pytest

from devops_quests.catalog import ROOT, Catalog
from devops_quests.runtime import Runtime

pytestmark = pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1", reason="Explicit local sandbox opt-in required"
)


def test_overlapping_owners_and_direct_deletion_cannot_prove_maintenance():
    runtime = Runtime(ROOT / ".state/runtime")
    catalog = Catalog()
    run = {"id": secrets.token_hex(12), "level": 85}
    folder = Path(os.environ.get("DQ_DEEPEN_EVIDENCE", ROOT / "artifacts/deepen-shortcuts"))
    folder.mkdir(parents=True, exist_ok=True)
    evidence = {"quest": 85, "run": run["id"]}
    try:
        runtime.create(run)
        runtime.exec(run, catalog.script(85, 0, "setup"), timeout=240)
        runtime.capture_facts(dict(run, stage=0), catalog.quests[85]["immutable"][0])
        # Check actual player authority, rather than trusting a Role manifest.
        denied = runtime.exec(run, '''set -euo pipefail
cd ~/quest
kubectl auth can-i patch pods --subresource=status || true
if kubectl create role receipt-writer --verb=patch --resource=pods/status; then exit 1; fi
if kubectl create rolebinding receipt-writer --role=player --serviceaccount="$DQ_NAMESPACE:player"; then exit 1; fi
if printf '[]' > /run/dq/observations/evictions.json; then exit 1; fi
''', check=False)
        assert denied.returncode == 0, denied.stderr
        assert denied.stdout.splitlines()[0] == "no"
        projects = runtime.kube(
            "-n", "dq-platform-" + run["id"], "get", "appprojects", "-o", "json"
        )
        assert [p["metadata"]["name"] for p in json.loads(projects.stdout)["items"]] == ["station"]
        # A direct live patch is reverted by the real controller.
        reverted = runtime.exec(run, '''set -euo pipefail
cd ~/quest
kubectl patch pdb relay --type=merge -p '{"spec":{"minAvailable":1}}'
for i in $(seq 1 40); do
 if kubectl get pdb relay -o json | jq -e '.spec.minAvailable==2' >/dev/null; then exit 0; fi
 sleep 1
done
exit 1
''', check=False, timeout=60)
        assert reverted.returncode == 0, reverted.stderr
        # Fix only the Git-owned cause: the second independent obstacle remains.
        reference = (ROOT / "solutions/085/0.sh").read_text()
        source_fix = reference.split("kubectl patch pdb companion", 1)[0]
        runtime.exec(run, source_fix, timeout=60)
        overlap = runtime.exec(run, '''set -euo pipefail
cd ~/quest
for i in $(seq 1 60); do
 if kubectl get pdb relay -o json | jq -e '.spec.minAvailable==1 and .status.disruptionsAllowed>=1' >/dev/null; then break; fi
 sleep 1
done
pod=$(kubectl get pods -l app=relay -o jsonpath='{.items[0].metadata.name}')
uid=$(kubectl get pod "$pod" -o jsonpath='{.metadata.uid}')
jq -n --arg pod "$pod" --arg ns "$DQ_NAMESPACE" --arg uid "$uid" '{apiVersion:"policy/v1",kind:"Eviction",metadata:{name:$pod,namespace:$ns},deleteOptions:{preconditions:{uid:$uid}}}' > /tmp/eviction.json
kubectl create --raw "/api/v1/namespaces/$DQ_NAMESPACE/pods/$pod/eviction" -f /tmp/eviction.json
''', check=False, timeout=90)
        assert overlap.returncode != 0
        assert "more than one PodDisruptionBudget" in overlap.stderr
        # A correct-looking request plus DELETE is not an Eviction API outcome.
        runtime.exec(run, '''set -euo pipefail
cd ~/quest
kubectl patch pdb companion --type=merge -p '{"spec":{"selector":{"matchExpressions":null,"matchLabels":{"app":"companion"}}}}'
printf '[]\n' > evictions.json
for pool in relay companion; do
 pod=$(kubectl get pods -l "app=$pool" -o jsonpath='{.items[0].metadata.name}')
 uid=$(kubectl get pod "$pod" -o jsonpath='{.metadata.uid}')
 jq --arg pod "$pod" --arg ns "$DQ_NAMESPACE" --arg uid "$uid" '.+[{apiVersion:"policy/v1",kind:"Eviction",metadata:{name:$pod,namespace:$ns},deleteOptions:{preconditions:{uid:$uid}}}]' evictions.json >/tmp/requests.json
 cp /tmp/requests.json evictions.json
 kubectl delete "pod/$pod" --wait=true --timeout=60s
 kubectl rollout status "deployment/$pool" --timeout=90s
done
''', timeout=180)
        runtime.observe(run)
        after = runtime.exec(run, catalog.script(85, 0, "check"), check=False, timeout=60)
        assert after.returncode != 0
        assert "[DQ:maintenance_evictions]" in after.stdout
        evidence.update(authority="denied", live_patch="reverted", overlap="rejected", direct_delete="rejected", diagnostics=after.stdout)
    except (Exception, subprocess.SubprocessError) as error:
        evidence["error"] = str(error)
        raise
    finally:
        try:
            runtime.teardown(run)
            evidence["teardown"] = "PASS"
        finally:
            (folder / "085-maintenance-boundaries.json").write_text(json.dumps(evidence, indent=2) + "\n")
