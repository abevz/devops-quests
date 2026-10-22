"""On-demand controllers cannot mutate another namespace or remove foreign objects."""

import json
from types import SimpleNamespace

import pytest

from devops_quests.components import Components


@pytest.mark.parametrize("identifier", ["../other", "foreign", "a" * 23 + "z"])
def test_component_identity_rejected_before_any_action(identifier):
    component = Components(SimpleNamespace())
    for action in (component.create, component.teardown):
        with pytest.raises(ValueError, match="identity"):
            action({"id": identifier})


def test_ingress_controller_mutation_permissions_stay_inside_target_namespace():
    calls = []
    run = {"id": "a" * 24, "level": 107}

    class Runtime:
        installation = "fixture"

        def __init__(self):
            self.images = {"traefik": "traefik@sha256:fixture"}

        def namespace(self, run):
            return "dq-" + run["id"]

        def kube(self, *args, input=None, **kwargs):
            if input:
                calls.append(json.loads(input))
            return SimpleNamespace(stdout="10.96.0.5")

    runtime = Runtime()
    env = Components(runtime).ingress(run)
    namespace = "dq-components-" + run["id"]
    assert env["INGRESS_IP"] == "10.96.0.5"
    deployment = next(item for item in calls if item["kind"] == "Deployment")
    pod = deployment["spec"]["template"]["spec"]
    assert deployment["metadata"]["namespace"] == namespace
    assert not any(
        pod.get(field) for field in ("hostNetwork", "hostPID", "hostIPC", "volumes")
    )
    worker = pod["containers"][0]
    assert (
        worker["image"] == runtime.images["traefik"]
        and worker["imagePullPolicy"] == "Never"
    )
    assert worker["resources"]["limits"]["memory"] == "128Mi"
    assert (
        "--providers.kubernetesingress.namespaces=" + runtime.namespace(run)
        in worker["args"]
    )
    for item in calls:
        if item["kind"] == "ClusterRole":
            assert all(
                set(rule["verbs"]) <= {"get", "list", "watch"} for rule in item["rules"]
            )
        if item["kind"] == "Role":
            assert item["metadata"]["namespace"] == runtime.namespace(run)
            mutations = [
                r
                for r in item["rules"]
                if not set(r["verbs"]) <= {"get", "list", "watch"}
            ]
            assert mutations == [
                {
                    "apiGroups": ["networking.k8s.io"],
                    "resources": ["ingresses/status"],
                    "verbs": ["update"],
                }
            ]


@pytest.mark.parametrize("foreign_kind", ["ingressclass", "namespace"])
def test_teardown_preflights_all_resources_and_refuses_foreign_run(foreign_kind):
    run = {"id": "a" * 24, "level": 107}
    deleted = []

    class Runtime:
        installation = "fixture"

        def dependencies(self, run):
            return {"ingress", "kubernetes"}

        def kube(self, *args, **kwargs):
            if args[0] == "delete":
                deleted.append(args)
                return SimpleNamespace(stdout="")
            labels = {
                "devops-quests.installation": self.installation,
                "devops-quests.run": run["id"],
            }
            if args[1] == foreign_kind:
                labels["devops-quests.run"] = "b" * 24
            return SimpleNamespace(stdout=json.dumps({"metadata": {"labels": labels}}))

        def remove_namespace(self, name):
            deleted.append(("namespace", name))

    with pytest.raises(RuntimeError, match="foreign"):
        Components(Runtime()).teardown(run)
    assert deleted == []
