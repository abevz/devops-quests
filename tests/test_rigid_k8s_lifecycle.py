"""Equivalent budgets, schedules and archives retain their observable contracts."""

import hashlib
import io
import json
import subprocess
import sys
import tarfile

import pytest
import yaml

from devops_quests.catalog import ROOT


def program(number, goal, marker):
    check = yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())[
        "stages"
    ][0]["objectives"][goal]["check"]
    return check.split("<<'" + marker + "'\n", 1)[1].split("\n" + marker, 1)[0]


def execute(number, marker, *arguments, cwd=None):
    return subprocess.run(
        [sys.executable, "-", *arguments],
        input=program(number, 0, marker),
        text=True,
        capture_output=True,
        timeout=5,
        cwd=cwd,
    )


@pytest.mark.parametrize("number,name", [(77, "board"), (85, "relay")])
@pytest.mark.parametrize(
    "field,value,accepted",
    [
        ("minAvailable", 1, True),
        ("minAvailable", "50%", True),
        ("maxUnavailable", 1, True),
        ("maxUnavailable", "50%", True),
        ("minAvailable", 2, True),
        ("minAvailable", 0, False),
        ("maxUnavailable", "100%", False),
        ("minAvailable", "bad", False),
    ],
)
def test_pdb_checks_effective_minimum(number, name, field, value, accepted):
    budget = {"spec": {field: value, "selector": {"matchLabels": {"app": name}}}}
    deployment = {
        "spec": {"replicas": 2, "template": {"metadata": {"labels": {"app": name}}}}
    }
    result = execute(
        number, "DQ_PDB", *map(json.dumps, [budget, deployment, {"items": []}])
    )
    assert (result.returncode == 0) is accepted


def test_pdb_equivalent_selector_cannot_protect_another_workload():
    deployment = {
        "spec": {
            "replicas": 2,
            "template": {"metadata": {"labels": {"app": "board", "pool": "station"}}},
        }
    }
    selector = {
        "matchExpressions": [{"key": "app", "operator": "In", "values": ["board"]}],
        "matchLabels": {"pool": "station"},
    }
    budget = {"spec": {"minAvailable": "50%", "selector": selector}}

    def run():
        return execute(
            77, "DQ_PDB", *map(json.dumps, [budget, deployment, {"items": []}])
        )

    assert run().returncode == 0
    selector["matchExpressions"][0]["values"] = ["board", "client"]
    assert run().returncode != 0
    selector["matchExpressions"][0]["values"] = ["client"]
    assert run().returncode != 0


@pytest.mark.parametrize(
    "schedule,accepted",
    [
        ("* * * * *", True),
        ("*/1 * * * *", True),
        ("0-59 0-23 1-31 1-12 0-6", True),
        ("* * * * 1-7", False),
        ("* * * * 0-7", False),
        ("* * * JAN-DEC SUN-SAT", True),
        ("0/1 0/1 1-31 * MON", True),
        ("* * * * MON", False),
        ("*/2 * * * *", False),
        ("0 * * * *", False),
        ("@hourly", False),
        ("* * * * * ignored", False),
        ("*/0 * * * *", False),
        ("60 * * * *", False),
    ],
)
def test_schedule_covers_every_minute(schedule, accepted):
    assert (execute(104, "DQ_CRON", schedule).returncode == 0) is accepted


def archive(path, names, payload=b"north-ledger\n", kind=tarfile.REGTYPE):
    with tarfile.open(path / "ledger.tar", "w") as target:
        for name in names:
            member = tarfile.TarInfo(name)
            member.type = kind
            if kind == tarfile.REGTYPE:
                member.size = len(payload)
                target.addfile(member, io.BytesIO(payload))
            else:
                member.linkname = "outside"
                target.addfile(member)


@pytest.mark.parametrize(
    "names,kind,accepted",
    [
        (["ledger.txt"], tarfile.REGTYPE, True),
        (["./ledger.txt"], tarfile.REGTYPE, True),
        (["././ledger.txt"], tarfile.REGTYPE, True),
        (["../ledger.txt"], tarfile.REGTYPE, False),
        (["/ledger.txt"], tarfile.REGTYPE, False),
        (["ledger.txt", "extra"], tarfile.REGTYPE, False),
        (["ledger.txt", "ledger.txt"], tarfile.REGTYPE, False),
        (["ledger.txt"], tarfile.SYMTYPE, False),
        (["ledger.txt"], tarfile.LNKTYPE, False),
    ],
)
def test_archive_accepts_only_one_safe_embedded_ledger(tmp_path, names, kind, accepted):
    archive(tmp_path, names, kind=kind)
    digest = hashlib.sha256(b"north-ledger\n").hexdigest()
    result = execute(128, "DQ_ARCHIVE", digest, cwd=tmp_path)
    assert (result.returncode == 0) is accepted


def test_archive_rejects_changed_bytes_and_missing_archive(tmp_path):
    digest = hashlib.sha256(b"north-ledger\n").hexdigest()
    archive(tmp_path, ["ledger.txt"], payload=b"wrong")
    assert execute(128, "DQ_ARCHIVE", digest, cwd=tmp_path).returncode != 0
    (tmp_path / "ledger.tar").unlink()
    assert execute(128, "DQ_ARCHIVE", digest, cwd=tmp_path).returncode != 0
