"""Shared primitives retain frozen pre-migration inline dialects."""

import ast
import copy
import functools
import io
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
from contextlib import redirect_stdout
from decimal import Decimal, localcontext
from types import SimpleNamespace

import pytest
import dq_check as helper
from scripts import asset_cache, prepare_assets

ROOT = Path(__file__).resolve().parents[1]
REFERENCES = json.loads(
    (ROOT / "tests/fixtures/check-helper-reference.json").read_text()
)["programs"]


@functools.lru_cache
def original(quest, tag, required=None):
    candidates = REFERENCES[f"{quest:03}:{tag}"]
    for candidate in candidates:
        body = candidate["python"]
        tree = ast.parse(body)
        if required is None or any(
            isinstance(node, ast.FunctionDef) and node.name == required
            for node in tree.body
        ):
            break
    else:
        raise AssertionError(f"No {tag} entrypoint defines {required} in quest {quest}")
    # Compile definitions, not the check's CLI calls, argv shim or process exit.
    definitions = [
        node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.ClassDef))
    ]
    namespace = dict(
        json=json,
        re=re,
        os=os,
        stat=stat,
        subprocess=subprocess,
        sys=sys,
        Path=Path,
        Decimal=Decimal,
    )
    exec(
        compile(
            ast.Module(body=definitions, type_ignores=[]),
            f"quest-{quest}-{tag}",
            "exec",
        ),
        namespace,
    )
    return namespace


def outcome(function, *args, **kwargs):
    output = io.StringIO()
    with redirect_stdout(output):
        try:
            value = function(*copy.deepcopy(args), **copy.deepcopy(kwargs))
        except Exception as error:
            return "error", type(error).__name__, str(error), output.getvalue()
    return "ok", value, output.getvalue()


@pytest.mark.parametrize(
    "quest,tag,dialect",
    [
        (34, "DQ_QUANTITY", "typed_ascii"),
        (68, "DQ_GIT_HEALTH", "unicode_finite"),
        (130, "DQ_BOSS", "coerced_ascii"),
    ],
)
@pytest.mark.parametrize(
    "value",
    [
        "100m",
        "100e-3",
        ".1",
        "16Mi",
        "16777216",
        "3Ki",
        "2Gi",
        "1n",
        "1u",
        "1k",
        "1K",
        "1E",
        "1Ei",
        "-5m",
        "0",
        0,
        0.2,
        True,
        False,
        None,
        [],
        {},
        "",
        " 1",
        "1 ",
        "NaN",
        "Inf",
        "1mi",
        "١٠٠m",
        Decimal(".1"),
        "1e9999999",
    ],
)
def test_quantity_dialects_match_actual_inline(quest, tag, dialect, value):
    reference = original(quest, tag)["quantity"]
    assert outcome(helper.quantity, value, dialect=dialect) == outcome(reference, value)


def test_finiteness_is_not_silently_added_to_other_dialects():
    with localcontext() as context:
        context.traps[__import__("decimal").Overflow] = False
        assert helper.quantity("1e9999999").is_infinite()
        assert helper.quantity("1e9999999", dialect="coerced_ascii").is_infinite()
        with pytest.raises(ValueError, match="quantity"):
            helper.quantity("1e9999999", dialect="unicode_finite")


SELECTORS = [
    None,
    {},
    [],
    {"extra": True},
    {"matchLabels": {"app": "board"}},
    {"matchExpressions": [{"key": "app", "operator": "In", "values": ["board"]}]},
    {"matchExpressions": [{"key": "app", "operator": "NotIn", "values": ["wrong"]}]},
    {"matchExpressions": [{"key": "app", "operator": "Exists"}]},
    {"matchExpressions": [{"key": "absent", "operator": "DoesNotExist"}]},
    {"matchExpressions": [{"key": "app", "operator": "Bogus"}]},
    {"matchExpressions": [{"operator": "DoesNotExist"}]},
    {"matchLabels": [], "matchExpressions": []},
]


@pytest.mark.parametrize(
    "quest,tag,dialect,name",
    [
        (77, "DQ_PDB", "pdb", "selected"),
        (119, "DQ_POLICY", "policy_optional", "matches"),
        (120, "DQ_BOSS", "policy_required", "matches"),
    ],
)
@pytest.mark.parametrize("selector", SELECTORS)
def test_selector_error_and_matching_dialects(quest, tag, dialect, name, selector):
    labels = {"app": "board", "tier": "front"}
    reference = original(quest, tag, name)[name]
    wanted = (
        outcome(reference, labels, selector)
        if name == "selected"
        else outcome(reference, selector, labels)
    )
    assert outcome(helper.selector_matches, labels, selector, dialect=dialect) == wanted


@pytest.mark.parametrize(
    "selector",
    SELECTORS
    + [
        {"matchLabels": {"app": "wrong"}},
        {
            "matchExpressions": [
                {"key": "app", "operator": "In", "values": ["board", "other"]},
                {"key": "app", "operator": "NotIn", "values": ["other"]},
            ]
        },
        {
            "matchLabels": {"app": "board"},
            "matchExpressions": [{"key": "extra", "operator": "Exists"}],
        },
    ],
)
def test_selector_equivalence_is_not_snapshot_matching(selector):
    labels = {"app": "board"}
    assert outcome(helper.selector_equivalent, selector, labels) == outcome(
        original(62, "DQ_INGRESS_POLICY")["simple_selector"], selector, labels
    )


@pytest.mark.parametrize(
    "items",
    [
        None,
        [],
        [{}],
        [{"name": "sidecar"}, {"name": "worker"}],
        [{"name": "worker"}] * 2,
        [None, {"name": "worker"}],
        ["noise", {"name": "worker"}],
    ],
)
def test_named_and_strict_worker_policies(items):
    assert outcome(helper.named, items, "worker") == outcome(
        original(27, "DQ_PRIVATE_PULL")["named"], items, "worker"
    )
    document = {"spec": {"template": {"spec": {"containers": items}}}}
    assert outcome(helper.workload_worker, document) == outcome(
        original(34, "DQ_QUANTITY")["worker"], document
    )
    assert outcome(
        helper.workload_worker,
        document,
        error="named identity",
        ignore_non_mappings=True,
    ) == outcome(original(130, "DQ_BOSS")["worker"], document)
    pod = {"spec": {"containers": items}}
    assert outcome(helper.optional_pod_worker, pod) == outcome(
        original(126, "DQ_ADMITTED")["worker"], pod
    )
    assert outcome(helper.pod_worker, pod) == outcome(
        original(27, "DQ_PRIVATE_PULL")["pod_worker"], pod
    )


@pytest.mark.parametrize(
    "value",
    [0, 2, -1, True, None, "1", "50%", "33%", "100%", "101%", "0%", "-1%", "1.5%"],
)
@pytest.mark.parametrize("replicas", [1, 2, 3])
def test_pdb_percentage_rounding(value, replicas):
    assert outcome(helper.pdb_amount, value, replicas) == outcome(
        original(77, "DQ_PDB")["amount"], value, replicas
    )


def test_pdb_exclusive_budget_and_inverse():
    assert helper.pdb_minimum({"minAvailable": "50%"}, 3) == 2
    assert helper.pdb_minimum({"maxUnavailable": "50%"}, 3) == 1
    for invalid in [{}, {"minAvailable": 1, "maxUnavailable": 1}]:
        with pytest.raises(ValueError, match="exclusive budget"):
            helper.pdb_minimum(invalid, 3)


def pod(image):
    return {
        "metadata": {
            "uid": "pod",
            "ownerReferences": [
                {"kind": "ReplicaSet", "uid": "rs", "controller": True}
            ],
        },
        "spec": {"containers": [{"name": "worker", "image": image}]},
        "status": {
            "phase": "Running",
            "containerStatuses": [
                {
                    "name": "worker",
                    "ready": True,
                    "state": {"running": {}},
                    "imageID": "containerd://" + image.split("@")[-1],
                }
            ],
        },
    }


@pytest.mark.parametrize(
    "variant",
    [
        "reference",
        "sidecar",
        "duplicate",
        "wrong-digest",
        "not-ready",
        "no-running",
        "wrong-phase",
        "wrong-name",
        "invalid-image",
        "missing-spec",
    ],
)
def test_ready_image_uses_worker_and_digest(variant):
    image = "fixture@sha256:" + "a" * 64
    document = pod(image)
    if variant == "sidecar":
        document["spec"]["containers"].insert(0, {"name": "observer"})
    if variant == "duplicate":
        document["spec"]["containers"] *= 2
    if variant == "wrong-digest":
        document["status"]["containerStatuses"][0]["imageID"] = "sha256:" + "b" * 64
    if variant == "not-ready":
        document["status"]["containerStatuses"][0]["ready"] = False
    if variant == "no-running":
        document["status"]["containerStatuses"][0]["state"] = {}
    if variant == "wrong-phase":
        document["status"]["phase"] = "Succeeded"
    if variant == "wrong-name":
        document["spec"]["containers"][0]["name"] = "other"
    if variant == "invalid-image":
        image = "fixture:latest"
    if variant == "missing-spec":
        document.pop("spec")
    assert outcome(helper.ready_image, document, image) == outcome(
        original(27, "DQ_PRIVATE_PULL")["ready_image"], document, image
    )


@pytest.mark.parametrize(
    "variant",
    [
        "reference",
        "terminating",
        "empty-deletion",
        "failed",
        "other-rs",
        "not-controller",
        "wrong-deployment",
        "bad-uid",
    ],
)
def test_current_pods_follow_ownership_and_terminal_policy(variant):
    deployment = {"metadata": {"uid": "deployment"}}
    replicasets = {
        "items": [
            {
                "metadata": {
                    "uid": "rs",
                    "ownerReferences": [
                        {"kind": "Deployment", "uid": "deployment", "controller": True}
                    ],
                }
            }
        ]
    }
    document = pod("fixture@sha256:" + "a" * 64)
    if variant == "terminating":
        document["metadata"]["deletionTimestamp"] = "now"
    if variant == "empty-deletion":
        document["metadata"]["deletionTimestamp"] = ""
    if variant == "failed":
        document["status"]["phase"] = "Failed"
    if variant == "other-rs":
        document["metadata"]["ownerReferences"][0]["uid"] = "other"
    if variant == "not-controller":
        document["metadata"]["ownerReferences"][0]["controller"] = 1
    if variant == "wrong-deployment":
        replicasets["items"][0]["metadata"]["ownerReferences"][0]["uid"] = "other"
    if variant == "bad-uid":
        deployment["metadata"]["uid"] = ""
    assert outcome(
        helper.current_pods, deployment, replicasets, {"items": [document]}
    ) == outcome(
        original(27, "DQ_PRIVATE_PULL")["current_pods"],
        deployment,
        replicasets,
        {"items": [document]},
    )


@pytest.mark.parametrize(
    "entries",
    [
        None,
        [],
        [{"name": "ROUTE", "value": "north"}],
        [{"name": "ROUTE", "value": "north"}, {"name": "ROUTE", "value": "south"}],
        [
            {
                "name": "SECRET",
                "valueFrom": {"secretKeyRef": {"name": "vault", "key": "route"}},
            }
        ],
        [{"name": "POD", "valueFrom": {"fieldRef": {"fieldPath": "metadata.name"}}}],
        [
            {
                "name": "CPU",
                "valueFrom": {
                    "resourceFieldRef": {"resource": "limits.cpu", "divisor": "1000m"}
                },
            }
        ],
        [{"name": "bad", "valueFrom": {"secretKeyRef": {}, "fieldRef": {}}}],
    ],
)
def test_environment_normalization_preserves_defaults_and_duplicates(entries):
    assert outcome(helper.env_values, entries) == outcome(
        original(68, "DQ_GIT_HEALTH")["env"], entries
    )


@pytest.mark.parametrize(
    "variant",
    [
        "reference",
        "named-port",
        "zero-period",
        "missing-probe",
        "multiple-handlers",
        "bool-port",
        "out-of-range",
        "exec",
        "grpc",
    ],
)
def test_health_probe_normalization(variant):
    container = {
        "readinessProbe": {"httpGet": {"port": 8080}},
        "ports": [{"name": "web", "containerPort": 8080}],
    }
    if variant == "named-port":
        container["readinessProbe"]["httpGet"]["port"] = "web"
    if variant == "zero-period":
        container["readinessProbe"]["periodSeconds"] = 0
    if variant == "missing-probe":
        container = {}
    if variant == "multiple-handlers":
        container["readinessProbe"]["exec"] = {"command": ["true"]}
    if variant == "bool-port":
        container["readinessProbe"]["httpGet"]["port"] = True
    if variant == "out-of-range":
        container["readinessProbe"]["httpGet"]["port"] = 0
    if variant == "exec":
        container["readinessProbe"] = {"exec": {"command": ["true"]}}
    if variant == "grpc":
        container["readinessProbe"] = {"grpc": {"port": 8080}}
    assert outcome(helper.health_probe, container) == outcome(
        original(68, "DQ_GIT_HEALTH")["probe"], container
    )


@pytest.mark.parametrize(
    "variant",
    [
        "equivalent",
        "wrong-resource",
        "extra-fields",
        "duplicate-name",
        "drop-cap",
        "ignore-behavior",
        "scalar-type",
    ],
)
def test_resource_subset_uses_original_quantity_and_named_list_rules(variant):
    reference = {
        "resources": {"requests": {"cpu": "100m"}},
        "env": [{"name": "ROUTE", "value": "north"}],
        "securityContext": {"capabilities": {"drop": ["ALL"]}},
    }
    current = copy.deepcopy(reference)
    current["resources"]["requests"]["cpu"] = "0.1"
    ignore = False
    if variant == "wrong-resource":
        current["resources"]["requests"]["cpu"] = "1"
    if variant == "extra-fields":
        current["other"] = "permitted"
    if variant == "duplicate-name":
        current["env"] *= 2
    if variant == "drop-cap":
        current["securityContext"]["capabilities"]["drop"].append("NET_RAW")
    if variant == "ignore-behavior":
        reference["args"] = ["old"]
        current["args"] = ["new"]
        ignore = True
    if variant == "scalar-type":
        reference["enabled"] = 1
        current["enabled"] = True
    assert outcome(
        helper.resource_subset, reference, current, ignore_behavior=ignore
    ) == outcome(
        original(68, "DQ_GIT_HEALTH")["subset"],
        reference,
        current,
        ignore_behavior=ignore,
    )


RECAPS = [
    "PLAY RECAP\napp1 : ok=2 changed=0 unreachable=0 failed=0\n",
    'task line\n{"stats":{"app1":{"ok":"2","changed":0,"failures":0,"dark":0}}}',
    '{"event":"playbook_on_stats","event_data":{"processed":{"app1":1},"ok":{"app1":2},"changed":{"app1":0},"failures":{"app1":0},"dark":{"app1":0}}}',
    '{"stats":{"app1":{"ok":true}}}',
    '{"stats":{"app1":{"failed":0,"failures":1}}}',
    '{"stats":{"app1":{"ok":1,"ok":2}}}',
    "PLAY RECAP\napp1 : ok=1 changed=0\napp1 : ok=2 changed=0\n",
    "PLAY RECAP\napp1 : ok=1 ok=2\n",
    '{"stats":{"app1":{"ok":1}}}\n{"stats":{"app2":{"ok":3}}}',
    "not a recap",
    "",
    '{"stats":[]}',
]


@pytest.mark.parametrize("text", RECAPS)
def test_ansible_recaps_use_original_ambiguity_rules(text):
    assert outcome(helper.ansible_recap, text) == outcome(
        original(25, "DQ_RECAP")["recap"], text
    )


@pytest.mark.parametrize(
    "quest,dialect", [(20, "by_counter"), (25, "by_host"), (74, "shared_marker")]
)
@pytest.mark.parametrize(
    "text",
    RECAPS[:3] + ["", '{"stats":{"app1":{"ok":2},"app2":{"ok":1},"app3":{"ok":1}}}'],
)
def test_recap_failure_messages_and_marker_dialects(tmp_path, quest, dialect, text):
    path = tmp_path / "recap.log"
    path.write_text(text)
    assert outcome(
        helper.require_recaps,
        path,
        {"changed": 0, "failed": 0},
        positive=("ok",),
        prefix="kept",
        dialect=dialect,
    ) == outcome(
        original(quest, "DQ_RECAP")["require_recaps"],
        path,
        {"changed": 0, "failed": 0},
        positive=("ok",),
        prefix="kept",
    )


@pytest.mark.parametrize("section", ["values", "planned_values"])
@pytest.mark.parametrize(
    "variant",
    [
        "reference",
        "child-module",
        "data-only",
        "bad-resources",
        "bad-child",
        "missing",
        "bool-number",
    ],
)
def test_tofu_resource_walk_and_managed_file_properties(
    tmp_path, monkeypatch, section, variant
):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "notice.txt").write_text("north")
    record = {
        "mode": "managed",
        "type": "local_file",
        "values": {"filename": "notice.txt"},
    }
    document = {section: {"root_module": {"resources": [record]}}}
    if variant == "child-module":
        document[section]["root_module"] = {
            "child_modules": [{"address": "module.child", "resources": [record]}]
        }
    if variant == "data-only":
        record["mode"] = "data"
    if variant == "bad-resources":
        document[section]["root_module"]["resources"] = {"not": "a-list"}
    if variant == "bad-child":
        document[section]["root_module"]["child_modules"] = [None]
    if variant == "missing":
        document = {}
    if variant == "bool-number":
        record["values"]["count"] = True
    reference = original(29, "DQ_PROPERTY")
    ours = helper.resource_records(document, section)
    theirs = reference["resource_records"](document, section)
    assert ours == theirs
    for in_module in [False, True]:
        assert outcome(helper.file_resources, ours, "notice.txt", in_module) == outcome(
            reference["file_resources"], theirs, "notice.txt", in_module
        )
    assert helper.number_is(True, 1) is False


@pytest.mark.parametrize(
    "name,existing",
    [
        ("notice.txt", True),
        ("./notice.txt", True),
        ("alias.txt", True),
        ("missing/../notice.txt", True),
        ("not-dir/../notice.txt", True),
        ("future.txt", False),
        ("notice.txt", False),
        ("", False),
        (None, False),
    ],
)
def test_file_aliases_keep_raw_traversal_and_existing_branches(
    tmp_path, monkeypatch, name, existing
):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "notice.txt").write_text("north")
    (tmp_path / "not-dir").write_text("file")
    (tmp_path / "alias.txt").symlink_to("notice.txt")
    expected = "notice.txt" if name != "future.txt" else "future.txt"
    assert outcome(helper.same_target, name, expected, existing) == outcome(
        original(29, "DQ_PROPERTY")["same_target"], name, expected, existing
    )


@pytest.mark.parametrize(
    "good,text", [(True, '{"a":1}'), (True, "invalid"), (False, '{"a":1}')]
)
def test_json_inputs_keep_cli_failure_semantics(tmp_path, monkeypatch, good, text):
    path = tmp_path / "data.json"
    path.write_text(text)
    assert outcome(helper.read_json, path, good) == outcome(
        original(29, "DQ_PROPERTY")["read_json"], path, good
    )
    monkeypatch.setattr(
        subprocess,
        "run",
        lambda *args, **kwargs: SimpleNamespace(
            returncode=0 if good else 1, stdout=text
        ),
    )
    assert outcome(helper.tofu_json, "show", "-json") == outcome(
        original(29, "DQ_PROPERTY")["tofu_json"], "show", "-json"
    )


@pytest.mark.parametrize(
    "quest,dialect,name,attribute,endpoint",
    [
        (64, "module", "station", "region", "var.region"),
        (98, "output", "route", "value", "local_file.notice.content"),
    ],
)
@pytest.mark.parametrize(
    "variant",
    [
        "reference",
        "transparent-wrapper",
        "locals",
        "cycle",
        "literal",
        "comment",
        "heredoc",
        "wrong-block",
        "json",
        "duplicate",
        "malformed",
    ],
)
def test_hcl_forwarder_dialects_keep_nonexecuting_parser(
    tmp_path, quest, dialect, name, attribute, endpoint, variant
):
    expression = endpoint
    prefix = ""
    if variant == "transparent-wrapper":
        expression = f'trimspace("${{{endpoint}}}")'
    if variant == "locals":
        prefix = f"locals {{\n route = {endpoint}\n}}\n"
        expression = "local.route"
    if variant == "cycle":
        prefix = "locals {\n route = local.other\n other = local.route\n}\n"
        expression = "local.route"
    if variant == "literal":
        expression = '"north"'
    body = f'{dialect} "{name}" {{\n{attribute} = {expression}\n}}\n'
    if variant == "comment":
        body = "# " + body.replace("\n", "\n# ")
    if variant == "heredoc":
        body = f"locals {{\n blob = <<EOF\n{body}EOF\n}}\n"
    if variant == "wrong-block":
        body = body.replace(f'{dialect} "', 'resource "', 1)
    if variant == "duplicate":
        body += body
    if variant == "malformed":
        body = body[:-3]
    if variant == "json":
        (tmp_path / "main.tf.json").write_text(
            json.dumps({dialect: {name: {attribute: "${" + expression + "}"}}})
        )
    else:
        (tmp_path / "main.tf").write_text(prefix + body)
    # The original predicates default to station/module or route/output respectively.
    assert outcome(
        helper.module_forwards, tmp_path, [expression], endpoint, dialect=dialect
    ) == outcome(
        original(quest, "DQ_PROPERTY" if quest == 64 else "DQ_REFERENCE")[
            "module_forwards"
        ],
        tmp_path,
        [expression],
        endpoint,
    )


@pytest.mark.parametrize(
    "text",
    [
        "local.route",
        "trimspace(local.route)",
        '"${local.route}"',
        "/* local.fake */ local.route",
        '"not a reference"',
        "<<EOF\nlocal.fake\nEOF\n",
        '"unterminated',
        "# fake\nlocal.route",
        'local["route"]',
    ],
)
def test_hcl_tokens_and_reference_rules_match_original(text):
    reference = original(64, "DQ_PROPERTY")
    assert outcome(helper.hcl_tokens, text) == outcome(reference["hcl_tokens"], text)
    if text != '"unterminated':
        assert outcome(helper.forward_reference, helper.hcl_tokens(text)) == outcome(
            reference["forward_reference"], reference["hcl_tokens"](text)
        )


def test_isolated_editable_import_uses_this_worktree_not_cwd(tmp_path):
    (tmp_path / "dq_check.py").write_text('raise RuntimeError("player shadow")')
    result = subprocess.run(
        [
            sys.executable,
            "-I",
            "-c",
            "import dq_check,devops_quests;print(dq_check.__file__);print(devops_quests.__file__)",
        ],
        cwd=tmp_path,
        env={**os.environ, "PYTHONPATH": str(tmp_path)},
        capture_output=True,
        text=True,
        check=True,
    )
    assert result.stdout.splitlines() == [
        str(ROOT / "dq_check.py"),
        str(ROOT / "devops_quests/__init__.py"),
    ]


def test_helper_source_is_a_receipt_input(tmp_path):
    assert "dq_check.py" in asset_cache.INPUTS
    for name in asset_cache.INPUTS:
        path = tmp_path / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("{}")
    before = asset_cache.inputs(tmp_path)
    (tmp_path / "dq_check.py").write_text("changed")
    assert asset_cache.inputs(tmp_path)["dq_check.py"] != before["dq_check.py"]


def test_prebuilt_lock_cannot_omit_helper_provenance(tmp_path, monkeypatch):
    (tmp_path / "build-images.lock.json").write_text(json.dumps({"inputs": {}}))
    monkeypatch.setattr(prepare_assets, "ROOT", tmp_path)
    monkeypatch.setattr(
        prepare_assets,
        "tools_only",
        lambda **kwargs: pytest.fail("stale images must not load"),
    )
    with pytest.raises(RuntimeError, match="input is missing.*dq_check.py"):
        prepare_assets.release_build()


@pytest.mark.parametrize(
    "payload", ["north\n", "north\n\n", "north\r\n", "маршрут\n", ""]
)
def test_descriptor_arguments_preserve_exact_here_string_bytes(payload):
    descriptor = os.memfd_create("dq-helper-argument")
    try:
        os.write(descriptor, payload.encode())
        os.lseek(descriptor, 0, os.SEEK_SET)
        actual = helper.read_argument(f"/dev/fd/{descriptor}")
        os.lseek(descriptor, 0, os.SEEK_SET)
        expected = original(27, "DQ_PRIVATE_PULL")["argument"](f"/dev/fd/{descriptor}")
        assert actual == expected == payload.removesuffix("\n")
        assert helper.read_argument("plain value") == "plain value"
    finally:
        os.close(descriptor)


@pytest.mark.parametrize(
    "dialect,quest,tag,name,attribute,endpoint",
    [
        ("module", 64, "DQ_PROPERTY", "station", "region", "var.region"),
        ("output", 98, "DQ_REFERENCE", "route", "value", "local_file.notice.content"),
    ],
)
def test_forwarder_explicit_none_is_not_the_default(
    tmp_path, dialect, quest, tag, name, attribute, endpoint
):
    (tmp_path / "main.tf").write_text(
        f'{dialect} "{name}" {{\n{attribute} = {endpoint}\n}}\n'
    )
    assert outcome(
        helper.module_forwards, tmp_path, [endpoint], endpoint, None, dialect=dialect
    ) == outcome(
        original(quest, tag)["module_forwards"], tmp_path, [endpoint], endpoint, None
    )


def test_prebuilt_lock_rejects_modified_helper_before_loading_images(
    tmp_path, monkeypatch
):
    import hashlib

    (tmp_path / "dq_check.py").write_text("changed")
    (tmp_path / "build-images.lock.json").write_text(
        json.dumps({"inputs": {"dq_check.py": hashlib.sha256(b"old").hexdigest()}})
    )
    monkeypatch.setattr(prepare_assets, "ROOT", tmp_path)
    monkeypatch.setattr(
        prepare_assets,
        "tools_only",
        lambda **kwargs: pytest.fail("stale helper must not load"),
    )
    with pytest.raises(RuntimeError, match="input changed.*dq_check.py"):
        prepare_assets.release_build()


@pytest.mark.parametrize(
    "function,args",
    [
        (helper.quantity, ("1",)),
        (helper.selector_matches, ({}, {})),
        (helper.require_recaps, ("missing.log", {})),
        (helper.module_forwards, ("missing", [], "endpoint")),
    ],
)
def test_unknown_dialects_do_not_fall_back_silently(function, args):
    with pytest.raises(ValueError, match="dialect"):
        function(*args, dialect="unknown")
