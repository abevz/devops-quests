"""084: stable-key state migration retains real object roles and volume bytes."""

import copy
import hashlib
import json
import os
import secrets
import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest

from devops_quests.catalog import ROOT, Catalog
from devops_quests.runtime import Runtime
from test_opentofu_rigid_checks import objective, python_source, state


def migration_fixture(worker_id="worker-original"):
    spec = {
        "worker_address": "module.station.docker_container.worker",
        "worker_name": "rail-worker",
        "network_address": "module.fabric.docker_network.backplane",
        "network_name": "rail-fabric",
        "routes_output": "routes",
        "plan_file": "migration-plan.json",
        "routes": {},
    }
    facts = {"worker_id": worker_id, "network_id": "network-original", "routes": {}}
    expected = {
        spec["worker_address"]: ("docker_container", worker_id),
        spec["network_address"]: ("docker_network", "network-original"),
    }
    live = {"rail-worker": {"Id": worker_id}, "rail-fabric": {"Id": "network-original"}}
    data = {}
    for key in ["north", "south"]:
        name = "rail-" + key
        volume = name + "-data"
        identity = key + "-original"
        data[name] = (key + "-retained\n").encode()
        spec["routes"][key] = {
            "container_address": f'module.route["{key}"].docker_container.worker',
            "volume_address": f'module.route["{key}"].docker_volume.ledger',
            "container_name": name,
            "volume_name": volume,
        }
        facts["routes"][key] = {
            "container_id": identity,
            "volume_name": volume,
            "volume_created_at": "2026-11-14T00:00:00Z",
            "data_sha256": hashlib.sha256(data[name]).hexdigest(),
        }
        expected[spec["routes"][key]["container_address"]] = (
            "docker_container",
            identity,
        )
        expected[spec["routes"][key]["volume_address"]] = ("docker_volume", volume)
        live[name] = {
            "Id": identity,
            "State": {"Running": True},
            "NetworkSettings": {
                "Networks": {"rail-fabric": {"NetworkID": "network-original"}}
            },
            "Mounts": [{"Destination": "/data", "Type": "volume", "Name": volume}],
        }
        live[volume] = {
            "Name": volume,
            "CreatedAt": facts["routes"][key]["volume_created_at"],
        }
    rows = []
    changes = []
    for address, (kind, identity) in expected.items():
        module = address.rsplit("." + kind + ".", 1)[0]
        rows.append(
            (
                module,
                {
                    "address": address,
                    "mode": "managed",
                    "type": kind,
                    "values": {"id": identity},
                },
            )
        )
        changes.append(
            {
                "address": address,
                "mode": "managed",
                "type": kind,
                "change": {
                    "actions": ["no-op"],
                    "before": {"id": identity},
                    "after": {"id": identity},
                },
            }
        )
    return spec, facts, state(*rows), {"resource_changes": changes}, live, data


def execute_probe(monkeypatch, tmp_path, index, variant):
    spec, facts, document, plan, live, data = migration_fixture()
    # Each keyed route module owns two resources in the actual nested layout.
    all_resources = [
        resource
        for child in document["values"]["root_module"]["child_modules"]
        for resource in child["resources"]
    ]
    if variant == "wrong-state-id":
        all_resources[0]["values"]["id"] = "replacement"
    elif variant == "wrong-address":
        all_resources[-1]["address"] = "module.foreign.docker_volume.ledger"
    elif variant == "state-extra":
        document["values"]["root_module"].setdefault("resources", []).append(
            {
                "address": "docker_volume.unrelated",
                "mode": "managed",
                "type": "docker_volume",
                "values": {"id": "unrelated"},
            }
        )
    elif variant == "state-duplicate":
        document["values"]["root_module"].setdefault("resources", []).append(
            copy.deepcopy(all_resources[0])
        )
    elif variant == "plan-extra":
        plan["resource_changes"].append(copy.deepcopy(plan["resource_changes"][0]))
    elif variant == "plan-id":
        plan["resource_changes"][-1]["change"]["after"]["id"] = "replacement"
    elif variant == "plan-replace":
        plan["resource_changes"][-1]["change"]["actions"] = ["delete", "create"]
    elif variant == "plan-kind":
        plan["resource_changes"][-1]["type"] = "local_file"
    elif variant == "bad-mode":
        plan["resource_changes"][0]["mode"] = "data"
    elif variant == "order-independent":
        plan["resource_changes"].reverse()
        document["values"]["root_module"]["child_modules"].reverse()
    elif variant == "readonly-data":
        extra = {
            "address": "data.docker_network.observed",
            "mode": "data",
            "type": "docker_network",
            "values": {"id": "network-original"},
        }
        document["values"]["root_module"]["resources"] = [extra]
        plan["resource_changes"].append(
            {
                "address": extra["address"],
                "mode": "data",
                "type": "docker_network",
                "change": {"actions": ["read"]},
            }
        )
    elif variant == "worker-replaced":
        live["rail-worker"]["Id"] = "replacement"
    elif variant == "route-replaced":
        live["rail-north"]["Id"] = "replacement"
    elif variant == "route-stopped":
        live["rail-north"]["State"]["Running"] = False
    elif variant == "network-replaced":
        live["rail-fabric"]["Id"] = "replacement"
    elif variant == "detached":
        live["rail-north"]["NetworkSettings"]["Networks"] = {}
    elif variant == "wrong-volume":
        live["rail-north"]["Mounts"][0]["Name"] = "rail-south-data"
    elif variant == "recreated-volume":
        live["rail-north-data"]["CreatedAt"] = "2026-11-15T00:00:00Z"
    elif variant == "ledger-crlf":
        data["rail-north"] = b"north-retained\r\n"
    monkeypatch.chdir(tmp_path)
    (tmp_path / "migration-plan.json").write_text(
        "{invalid" if variant == "malformed-plan" else json.dumps(plan)
    )
    original_read = Path.read_text

    def read(path, *args, **kwargs):
        if str(path) == "/run/dq/facts/0/module-contract.json":
            return json.dumps(spec)
        if str(path) == "/run/dq/facts/0/migration-identities.json":
            if variant == "missing-facts":
                raise FileNotFoundError(path)
            return json.dumps(facts)
        return original_read(path, *args, **kwargs)

    def cli(argv, **kwargs):
        if argv[0] == "tofu":
            if argv[1] == "show":
                output = document
            else:
                output = {
                    key: value["container_id"] for key, value in facts["routes"].items()
                }
                if variant == "swapped-output":
                    output = {"north": "south-original", "south": "north-original"}
            return SimpleNamespace(returncode=0, stdout=json.dumps(output), stderr="")
        assert argv[0] == "docker"
        if variant == "cli-failed":
            raise subprocess.CalledProcessError(1, argv)
        if argv[1] == "exec":
            return SimpleNamespace(returncode=0, stdout=data[argv[2]], stderr=b"")
        return SimpleNamespace(
            returncode=0, stdout=json.dumps([live[argv[-1]]]), stderr=""
        )

    monkeypatch.setattr(Path, "read_text", read)
    monkeypatch.setattr(subprocess, "run", cli)
    tag = ["DQ_MIGRATION_BINDINGS", "DQ_MIGRATION_IDENTITIES"][index]
    code = python_source(objective("084", index), tag)
    try:
        exec(compile(code, "084-migration-contract", "exec"), {"__name__": "__main__"})
    except SystemExit as result:
        return result.code or 0
    return 0


@pytest.mark.parametrize(
    "variant",
    [
        "reference",
        "order-independent",
        "readonly-data",
        "missing-facts",
        "wrong-address",
        "state-extra",
        "state-duplicate",
        "plan-extra",
        "plan-id",
        "plan-replace",
        "plan-kind",
        "bad-mode",
        "malformed-plan",
    ],
)
def test_managed_migration_contract(monkeypatch, tmp_path, variant):
    assert execute_probe(monkeypatch, tmp_path, 0, variant) == (
        0 if variant in ["reference", "order-independent", "readonly-data"] else 1
    )


@pytest.mark.parametrize(
    "variant",
    [
        "reference",
        "wrong-state-id",
        "worker-replaced",
        "route-replaced",
        "route-stopped",
        "network-replaced",
        "detached",
        "wrong-volume",
        "recreated-volume",
        "ledger-crlf",
        "swapped-output",
        "cli-failed",
    ],
)
def test_live_objects_data_and_role_outputs(monkeypatch, tmp_path, variant):
    assert execute_probe(monkeypatch, tmp_path, 1, variant) == (
        0 if variant == "reference" else 1
    )


@pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1",
    reason="Explicit local sandbox opt-in required",
)
def test_old_single_worker_refactor_does_not_complete():
    catalog = Catalog()
    runtime = Runtime(ROOT / ".state/runtime")
    run = {"id": secrets.token_hex(12), "level": 84}
    folder = Path(
        os.environ.get(
            "DQ_DEEPEN_EVIDENCE", ROOT / "artifacts/module-migration-shortcuts"
        )
    )
    folder.mkdir(parents=True, exist_ok=True)
    log = {"quest": 84, "old_source": "ae87ab32c5c4c8343cc56b33dc3828e691485224"}
    try:
        runtime.create(run)
        runtime.exec(
            run,
            "set -euo pipefail\ncd ~/quest\n" + catalog.script(84, 0, "setup"),
            timeout=240,
        )
        runtime.capture_facts(dict(run, stage=0), catalog.quests[84]["immutable"][0])
        check = catalog.script(84, 0, "check")
        assert runtime.exec(run, check, check=False, timeout=90).returncode != 0
        fixed = runtime.exec(
            run,
            (ROOT / "tests/fixtures/deepen-module-migration/084.sh").read_text(),
            check=False,
            timeout=240,
        )
        assert fixed.returncode == 0, fixed.stdout + fixed.stderr
        # The complete audited quest passes; the retained broader topology does not.
        legacy = runtime.exec(
            run,
            (
                ROOT / "tests/fixtures/deepen-module-migration/084-legacy-check.sh"
            ).read_text(),
            check=False,
            timeout=90,
        )
        assert legacy.returncode == 0, legacy.stdout + legacy.stderr
        after = runtime.exec(run, check, check=False, timeout=90)
        assert after.returncode != 0
        assert (
            "[DQ:migration_bindings]" in after.stdout
            and "[DQ:migration_identity]" in after.stdout
        )
        log.update(
            initial="FAIL as expected",
            old_fix_exit=fixed.returncode,
            old_complete_check="PASS",
            after_old_fix=after.stdout,
        )
    finally:
        try:
            runtime.teardown(run)
            log["teardown"] = "PASS"
        finally:
            (folder / "084-old-fix.json").write_text(json.dumps(log, indent=2) + "\n")


@pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1",
    reason="Explicit local sandbox opt-in required",
)
def test_retained_volume_bytes_are_not_established_by_an_empty_plan():
    catalog = Catalog()
    runtime = Runtime(ROOT / ".state/runtime")
    run = {"id": secrets.token_hex(12), "level": 84}
    folder = Path(
        os.environ.get(
            "DQ_DEEPEN_EVIDENCE", ROOT / "artifacts/module-migration-shortcuts"
        )
    )
    folder.mkdir(parents=True, exist_ok=True)
    log = {"quest": 84}
    try:
        runtime.create(run)
        runtime.exec(
            run,
            "set -euo pipefail\ncd ~/quest\n" + catalog.script(84, 0, "setup"),
            timeout=240,
        )
        runtime.capture_facts(dict(run, stage=0), catalog.quests[84]["immutable"][0])
        runtime.exec(run, (ROOT / "solutions/084/0.sh").read_text(), timeout=240)
        check = catalog.script(84, 0, "check")
        assert runtime.exec(run, check, check=False, timeout=90).returncode == 0
        runtime.exec(
            run,
            """cd ~/quest
docker exec rail-north cat /data/ledger > /tmp/original-ledger
printf 'north-retained\\r\\n' | docker exec -i rail-north sh -c 'cat > /data/ledger'
tofu plan -input=false -detailed-exitcode -no-color
""",
            timeout=90,
        )
        legacy = runtime.exec(
            run,
            (
                ROOT / "tests/fixtures/deepen-module-migration/084-legacy-check.sh"
            ).read_text(),
            check=False,
            timeout=90,
        )
        assert legacy.returncode == 0
        changed = runtime.exec(run, check, check=False, timeout=90)
        assert changed.returncode != 0 and "[DQ:migration_identity]" in changed.stdout
        runtime.exec(
            run,
            "docker exec -i rail-north sh -c 'cat > /data/ledger' < /tmp/original-ledger\n",
            timeout=30,
        )
        assert runtime.exec(run, check, check=False, timeout=90).returncode == 0
        log.update(
            original_solution="PASS",
            legacy_check_with_changed_bytes="PASS",
            changed_bytes=changed.stdout,
            restored="PASS",
        )
    finally:
        try:
            runtime.teardown(run)
            log["teardown"] = "PASS"
        finally:
            (folder / "084-data.json").write_text(json.dumps(log, indent=2) + "\n")
