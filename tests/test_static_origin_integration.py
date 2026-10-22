"""A player-created Pod cannot impersonate a file-backed kubelet workload."""

import json
import os
import secrets
import shlex

import pytest

from devops_quests.catalog import ROOT
from devops_quests.runtime import Runtime
from devops_quests.static_pods import file_origin, manifest

pytestmark = pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1",
    reason="Explicit owned sandbox opt-in required",
)


def test_kubelet_view_rejects_a_player_created_mirror_counterfeit():
    runtime = Runtime(ROOT / ".state/runtime")
    run = {"id": secrets.token_hex(12), "level": 117}
    owned = runtime.cluster + "-control-plane"
    name = "static-board-" + owned
    namespace = runtime.namespace(run)
    try:
        runtime.create(run)
        expected = manifest(runtime, run, 8080)
        counterfeit = json.loads(json.dumps(expected))
        counterfeit["metadata"]["name"] = name
        counterfeit["metadata"]["annotations"] = {"kubernetes.io/config.source": "file"}
        # Runtime creates this account synchronously; the namespace controller
        # need not have created default yet. This is an ordinary API Pod.
        counterfeit["spec"]["serviceAccountName"] = "player"
        runtime.exec(
            run,
            "set -euo pipefail\ncd ~/quest\ncat > counterfeit.json <<'COUNTERFEIT'\n"
            + json.dumps(counterfeit)
            + "\nCOUNTERFEIT\nkubectl create -f counterfeit.json\nkubectl wait --for=condition=Ready pod/"
            + name
            + " --timeout=45s\n",
        )
        uid = runtime.exec(
            run, "kubectl get pod " + name + " -o jsonpath='{.metadata.uid}'"
        ).stdout.strip()
        rejected = runtime.exec(
            run,
            "kubectl annotate pod "
            + name
            + " "
            + shlex.quote("kubernetes.io/config.mirror=" + uid)
            + " --overwrite\n",
            check=False,
        )
        assert (
            rejected.returncode != 0
            and "may not add mirror pod annotation" in rejected.stderr
        )
        mirror = json.loads(
            runtime.kube("-n", namespace, "get", "pod", name, "-o", "json").stdout
        )
        pods = json.loads(
            runtime.kube(
                "get",
                "--raw=/api/v1/nodes/" + owned + "/proxy/pods",
                "--request-timeout=3s",
            ).stdout
        )["items"]
        selected = [
            p
            for p in pods
            if p["metadata"].get("namespace") == namespace
            and p["metadata"]["name"] == name
        ]
        assert all(
            p["metadata"].get("annotations", {}).get("kubernetes.io/config.source")
            != "file"
            for p in selected
        )
        cri = json.loads(
            runtime.docker(
                "exec",
                owned,
                "crictl",
                "pods",
                "--name",
                "static-board",
                "--namespace",
                namespace,
                "-o",
                "json",
            ).stdout
        )["items"]
        assert not file_origin(pods, cri, mirror, expected, owned)
        evidence = {
            "ordinary_api_pod_ready_before_spoof": True,
            "mirror_annotation_update_rejected": True,
            "api_source_annotation_is_player_controlled": mirror["metadata"][
                "annotations"
            ]["kubernetes.io/config.source"]
            == "file",
            "kubelet_file_source_for_counterfeit": False,
            "counterfeit_proof_rejected": True,
        }
        folder = ROOT / "artifacts/quests"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "117-counterfeit.json").write_text(
            json.dumps(evidence, indent=2) + "\n"
        )
        runtime.exec(run, "kubectl delete pod " + name + " --wait=true --timeout=30s\n")
    finally:
        runtime.teardown(run)
