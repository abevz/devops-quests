"""Ownership and scope of on-demand book controllers."""

import json
from pathlib import Path
from types import SimpleNamespace

import pytest

from devops_quests.book_components import BookComponents

ROOT = Path(__file__).resolve().parents[1]
RUN = {"id": "a" * 24, "level": 130}


class FixtureRuntime:
    root = ROOT
    installation = "fixture"

    def __init__(self):
        self.images = {
            "metrics": "metrics@sha256:pinned",
            "traefik": "traefik@sha256:pinned",
        }
        self.objects = []
        self.loaded = []
        self.foreign = None
        self.deleted = []

    def namespace(self, run):
        return "dq-" + run["id"]

    def dependencies(self, run):
        return {"metrics", "gateway", "kubernetes"}

    def load_image(self, name):
        self.loaded.append(name)

    def kube(self, *args, **kwargs):
        if args[:2] == ("create", "-f"):
            self.objects.append(json.loads(kwargs["input"]))
        if "delete" in args:
            self.deleted.append(args)
        if "get" in args:
            at = args.index("get")
            kind, name = args[at + 1 : at + 3]
            if self.foreign == (kind, name):
                return SimpleNamespace(
                    stdout=json.dumps(
                        {
                            "metadata": {
                                "labels": {"devops-quests.installation": "foreign"}
                            }
                        }
                    )
                )
        return SimpleNamespace(stdout="")

    def remove_namespace(self, name):
        self.deleted.append(("namespace", name))


def test_metrics_does_not_replace_registered_api_or_modify_aggregate_roles(monkeypatch):
    monkeypatch.setattr("devops_quests.book_runtime.metrics_route", lambda *args: None)
    r = FixtureRuntime()
    c = BookComponents(r)
    r.foreign = ("apiservice", "v1beta1.metrics.k8s.io")
    with pytest.raises(RuntimeError, match="existing metrics"):
        c.metrics(RUN)
    assert not r.objects and not r.loaded
    r.foreign = None
    c.metrics(RUN)
    assert r.loaded == ["metrics"]
    assert not any(
        o["metadata"]
        .get("labels", {})
        .get("rbac.authorization.k8s.io/aggregate-to-admin")
        for o in r.objects
    )
    assert all(o["metadata"]["labels"] == c.labels(RUN) for o in r.objects)
    api = next(o for o in r.objects if o["kind"] == "APIService")
    assert api["spec"]["service"]["namespace"] == c.namespace(RUN)
    dep = next(o for o in r.objects if o["kind"] == "Deployment")
    container = dep["spec"]["template"]["spec"]["containers"][0]
    assert container["image"] == r.images["metrics"]
    assert container["resources"]["limits"] == {"cpu": "300m", "memory": "256Mi"}
    assert (
        dep["spec"]["template"]["spec"]["serviceAccountName"]
        == "dq-metrics-" + RUN["id"]
    )


@pytest.mark.parametrize(
    "foreign",
    [
        ("apiservice", "v1beta1.metrics.k8s.io"),
        ("gatewayclass", "dq-gateway-" + RUN["id"]),
        ("namespace", "dq-book-" + RUN["id"]),
    ],
)
def test_cleanup_preflights_every_object_before_deletion(foreign):
    r = FixtureRuntime()
    r.foreign = foreign
    with pytest.raises(RuntimeError, match="foreign"):
        BookComponents(r).teardown(RUN)
    assert not r.deleted


def test_gateway_has_only_owned_status_write_at_cluster_scope():
    r = FixtureRuntime()
    c = BookComponents(r)
    env = c.gateway(RUN)
    assert env["GATEWAY_CLASS"] == "dq-gateway-" + RUN["id"]
    assert not any(o["kind"].startswith("ValidatingAdmission") for o in r.objects)
    cluster = next(o for o in r.objects if o["kind"] == "ClusterRole")
    writes = [rule for rule in cluster["rules"] if "update" in rule["verbs"]]
    assert writes == [
        {
            "apiGroups": ["gateway.networking.k8s.io"],
            "resources": ["gatewayclasses/status"],
            "resourceNames": [env["GATEWAY_CLASS"]],
            "verbs": ["update"],
        }
    ]
    role = next(o for o in r.objects if o["kind"] == "Role")
    assert role["metadata"]["namespace"] == r.namespace(RUN)
    dep = next(o for o in r.objects if o["kind"] == "Deployment")
    args = dep["spec"]["template"]["spec"]["containers"][0]["args"]
    assert "--providers.kubernetesgateway.namespaces=" + r.namespace(RUN) in args
    assert (
        "--providers.kubernetesgateway.labelselector=devops-quests.run=" + RUN["id"]
        in args
    )


def test_gateway_refuses_foreign_crd():
    r = FixtureRuntime()
    import yaml

    crd = next(yaml.safe_load_all((ROOT / "vendor/gateway-api.yaml").read_text()))
    r.foreign = ("crd", crd["metadata"]["name"])
    with pytest.raises(RuntimeError, match="foreign Gateway"):
        BookComponents(r).gateway(RUN)
    assert not r.objects


def test_metrics_route_never_overwrites_an_existing_node_route(tmp_path, monkeypatch):
    from devops_quests.book_runtime import metrics_route

    monkeypatch.setattr(
        "devops_quests.owned_kind.owned_node", lambda *args: "owned-node"
    )

    class Runtime:
        state = tmp_path
        installation = "owner"

        def docker(self, *args, **kwargs):
            assert args == (
                "exec",
                "owned-node",
                "ip",
                "-j",
                "route",
                "show",
                "exact",
                "10.96.2.3/32",
            )
            return SimpleNamespace(stdout='[{"dst":"10.96.2.3","dev":"foreign"}]')

    with pytest.raises(RuntimeError, match="existing metrics VIP route"):
        metrics_route(Runtime(), RUN, "10.96.2.3")
    assert list(tmp_path.iterdir()) == []
