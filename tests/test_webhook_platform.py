"""Only webhook quests receive a private receiver and disabled Git polling."""

import json
import subprocess

import pytest
import yaml

from devops_quests.catalog import ROOT
from devops_quests.platform import Platform


@pytest.mark.parametrize("level", [54, 75, 123])
def test_webhook_receiver_is_on_demand_and_uses_pinned_image(level, monkeypatch):
    objects, files = [], {}

    class Runtime:
        root = ROOT
        images = json.loads((ROOT / "images.lock.json").read_text())
        network = "owned-bridge"
        installation = "fixture"
        cluster = "devops-quests-0123456789"

        def namespace(self, run):
            return "dq-" + run["id"]

        def dependencies(self, run):
            return {"argocd", "applicationset"} if run["level"] == 123 else {"argocd"}

        def kube(self, *args, input=None, **kwargs):
            if input:
                objects.extend(yaml.safe_load_all(input))
            return subprocess.CompletedProcess(
                [],
                0,
                json.dumps({"spec": {"ports": [{"name": "http", "nodePort": 30123}]}}),
                "",
            )

        def load_image(self, key):
            assert key in ("argocd", "redis")

        def inspect(self, name):
            assert name == self.cluster + "-control-plane"
            return {
                "NetworkSettings": {
                    "Networks": {self.network: {"IPAddress": "172.28.0.2"}}
                }
            }

    platform = Platform(Runtime())
    monkeypatch.setattr(platform, "put", lambda run, n, text: files.update({n: text}))
    platform.argocd(
        {"id": "a" * 24, "level": level},
        {
            "GIT_URL": "http://owned-gitea:3000/rail/station.git",
            "GIT_USER": "rail",
            "GIT_PASSWORD": "fixture-password",
        },
    )
    server = [
        o
        for o in objects
        if o.get("kind") == "Deployment" and o["metadata"]["name"] == "argocd-server"
    ]
    cm = next(
        o
        for o in objects
        if o.get("kind") == "ConfigMap" and o["metadata"]["name"] == "argocd-cm"
    )
    if level == 75:
        assert len(server) == 1
        container = server[0]["spec"]["template"]["spec"]["containers"][0]
        assert container["image"] == Runtime.images["argocd"]
        assert "--insecure" in container["args"]
        assert "hostNetwork" not in server[0]["spec"]["template"]["spec"]
        assert cm["data"]["timeout.reconciliation"] == "0"
        params = next(
            o
            for o in objects
            if o.get("kind") == "ConfigMap"
            and o["metadata"]["name"] == "argocd-cmd-params-cm"
        )
        assert params["data"]["server.log.format"] == "json"
        secret = next(
            o
            for o in objects
            if o.get("kind") == "Secret" and o["metadata"]["name"] == "argocd-secret"
        )
        assert len(secret["stringData"]["webhook.gogs.secret"]) >= 32
        assert json.loads(files["webhook-target.json"])["url"] == (
            "http://172.28.0.2:30123/api/webhook"
        )
    else:
        assert server == [] and files == {}
        assert cm["data"]["timeout.reconciliation"] == "15s"
    controllers = [
        o
        for o in objects
        if o.get("kind") == "Deployment"
        and o["metadata"]["name"] == "argocd-applicationset-controller"
    ]
    if level == 123:
        assert len(controllers) == 1
        worker = controllers[0]["spec"]["template"]["spec"]["containers"][0]
        assert worker["resources"]["limits"] == {"cpu": "300m", "memory": "192Mi"}
        assert not any("--applicationset-namespaces" in arg for arg in worker["args"])
        assert not any(
            o["kind"] == "ClusterRoleBinding"
            and o["roleRef"]["name"] == "argocd-applicationset-controller"
            for o in objects
        )
        params = next(
            o
            for o in objects
            if o["kind"] == "ConfigMap"
            and o["metadata"]["name"] == "argocd-cmd-params-cm"
        )
        assert (
            params["data"]["applicationsetcontroller.enable.scm.providers"] == "false"
        )
    else:
        assert controllers == []
