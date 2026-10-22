"""Compare owned cleanup with a pre-existing Docker resource inventory."""

import argparse
import fcntl
import json
import subprocess
from pathlib import Path

from devops_quests.catalog import ROOT
from devops_quests.runtime import DOCKER, Runtime


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    r = Runtime(ROOT / ".state/runtime")
    installation_lock = (r.state / "server.lock").open("a")
    try:
        fcntl.flock(installation_lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise RuntimeError(
            "Stop the app and real integration tests before reset"
        ) from None
    r.reset()
    rules = r.docker(
        "run",
        "--rm",
        *r.labels(),
        "--network",
        "host",
        "--cap-drop",
        "ALL",
        "--cap-add",
        "NET_ADMIN",
        "--entrypoint",
        "/usr/sbin/iptables-save",
        r.image,
    ).stdout
    owned_rules = [
        line
        for line in rules.splitlines()
        if "DQ" + r.installation.upper() in line
        or "devops-quests-" + r.installation in line
    ]
    commands = {
        "containers": ["ps", "-aq", "--no-trunc"],
        "networks": ["network", "ls", "-q", "--no-trunc"],
        "volumes": ["volume", "ls", "-q"],
        "images": ["image", "ls", "-q", "--no-trunc"],
    }
    current = {
        key: set(subprocess.check_output([*DOCKER, *value], text=True).split())
        for key, value in commands.items()
    }
    baseline = json.loads(args.baseline.read_text())
    # Docker's initial ps/network inventory used 12-character IDs, while
    # image IDs were already full sha256 values. Match unique ID prefixes;
    # never interpret that representation difference as resource deletion.
    missing = {}
    for key, values in baseline.items():
        if key in {"containers", "networks"}:
            matches = {
                old: [now for now in current[key] if now.startswith(old)]
                for old in values
            }
            if any(len(candidates) > 1 for candidates in matches.values()):
                raise RuntimeError("Ambiguous inventory ID prefix")
            missing[key] = sorted(
                old for old, candidates in matches.items() if not candidates
            )
        else:
            missing[key] = sorted(set(values) - current[key])
    proof = {
        "baseline_missing": missing,
        "owned_firewall_rules_after_reset": owned_rules,
        "baseline_id_matching": "unique prefixes for container/network IDs; full volume/image IDs",
    }
    proof["owned_containers"] = r.docker(
        "ps", "-aq", "--filter", "label=devops-quests=true"
    ).stdout.split()
    proof["owned_networks"] = r.docker(
        "network", "ls", "-q", "--filter", "label=devops-quests=true"
    ).stdout.split()
    proof["owned_volumes"] = r.docker(
        "volume", "ls", "-q", "--filter", "label=devops-quests=true"
    ).stdout.split()
    proof["private_bay_directories"] = (
        [p.name for p in (r.state / "bays").iterdir()]
        if (r.state / "bays").exists()
        else []
    )
    proof["kind_node_present"] = bool(r.inspect(r.cluster + "-control-plane"))
    proof["new_unlabeled_volumes"] = sorted(
        current["volumes"] - set(baseline["volumes"])
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(proof, indent=2) + "\n")
    assert not any(proof["baseline_missing"].values()), (
        "A baseline resource is missing: inspect evidence before attribution"
    )
    assert not any(
        proof[x]
        for x in (
            "private_bay_directories",
            "owned_containers",
            "owned_networks",
            "owned_volumes",
            "kind_node_present",
            "new_unlabeled_volumes",
            "owned_firewall_rules_after_reset",
        )
    )
    print("Full reset and baseline preservation: PASS")


if __name__ == "__main__":
    main()
