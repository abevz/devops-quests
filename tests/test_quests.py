"""Real integration contract: same workstation exec path as interactive players."""

import asyncio
import hashlib
import json
import os
import re
import secrets
import subprocess
import threading
import time

import pytest

from devops_quests.catalog import RELEASED, ROOT, Catalog
from devops_quests.runtime import Runtime

pytestmark = pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1",
    reason="Explicit local sandbox opt-in required",
)


def wait_098_convergence(runtime, run, check, old_pods, old_sets):
    """Integration only: rolling updates can briefly route to a retiring Pod.

    The game polls every 2.5s. Allow at most 30s here, requiring three
    consecutive successes and independently proving the old rollout retired.
    Owner decision #2 permits old terminating Pods outside ready endpoints.
    """
    deadline = time.monotonic() + 30
    successes = 0
    last = "No response observed"
    while time.monotonic() < deadline:
        try:
            observed = runtime.exec(
                run, check, check=False, timeout=max(0.001, deadline - time.monotonic())
            )
            last = observed.stderr + "\n" + observed.stdout
            successes = successes + 1 if observed.returncode == 0 else 0
            if successes >= 3:
                snapshot = runtime.kube(
                    "-n", runtime.namespace(run), "get", "pods,replicasets",
                    "-l", "app=board", "-o", "json",
                    timeout=max(0.001, deadline - time.monotonic()),
                )
                items = json.loads(snapshot.stdout)["items"]
                endpoints = runtime.kube(
                    "-n", runtime.namespace(run), "get", "endpointslices",
                    "-l", "kubernetes.io/service-name=board", "-o", "json",
                    timeout=max(0.001, deadline - time.monotonic()),
                )
                ready = [
                    endpoint
                    for item in json.loads(endpoints.stdout)["items"]
                    for endpoint in item.get("endpoints", [])
                    if endpoint.get("conditions", {}).get("ready") is not False
                ]
                remaining_pods = [
                    item for item in items
                    if item["kind"] == "Pod" and (
                        item["metadata"]["uid"] in old_pods
                        or any(
                            owner.get("kind") == "ReplicaSet"
                            and owner.get("controller") is True
                            and owner.get("uid") in old_sets
                            for owner in item["metadata"].get("ownerReferences", [])
                        )
                    )
                ]
                pods_retired = all(
                    item["metadata"].get("deletionTimestamp")
                    and not any(
                        endpoint.get("targetRef", {}).get("uid") == item["metadata"]["uid"]
                        or (endpoint.get("targetRef", {}).get("name")
                            and endpoint["targetRef"]["name"] == item["metadata"].get("name"))
                        or set(endpoint.get("addresses", [])) & {
                            address["ip"] for address in item.get("status", {}).get("podIPs", [])
                        }
                        or item.get("status", {}).get("podIP") in endpoint.get("addresses", [])
                        for endpoint in ready
                    )
                    for item in remaining_pods
                )
                sets_retired = all(
                    item.get("spec", {}).get("replicas", 0) == 0
                    and item.get("status", {}).get("replicas", 0) == 0
                    for item in items
                    if item["kind"] == "ReplicaSet" and item["metadata"]["uid"] in old_sets
                )
                if pods_retired and sets_retired:
                    assert time.monotonic() <= deadline, last
                    return observed
                last += "\nOld board Pods terminating outside ready endpoints: " + str(pods_retired)
                last += "\nReady endpoints: " + json.dumps(ready)
                last += "\nOld Pod observations: " + json.dumps([
                    {"uid": item["metadata"]["uid"], "status": item.get("status", {})}
                    for item in remaining_pods
                ])
                last += "\nOld board ReplicaSets scaled to zero: " + str(sets_retired)
        except subprocess.TimeoutExpired as error:
            last += "\n" + str(error)
            break
        remaining = deadline - time.monotonic()
        if remaining > 0:
            time.sleep(min(1, remaining))
    pytest.fail("098 did not converge within 30s; last response:\n" + last)


@pytest.mark.parametrize("number", RELEASED)
def test_quest(number):
    catalog = Catalog()
    assert number in catalog.quests, f"Quest {number} is missing"
    runtime = Runtime(ROOT / ".state/runtime")
    run = {"id": secrets.token_hex(12), "level": number}
    evidence = ROOT / "artifacts/quests"
    evidence.mkdir(parents=True, exist_ok=True)
    log = [
        {
            "quest_sha256": hashlib.sha256(
                (ROOT / "quests" / f"{number:03}" / "quest.yaml").read_bytes()
            ).hexdigest()
        }
    ]
    try:
        runtime.create(run)
        if "ansible" in runtime.dependencies(run):
            host_keys = [
                runtime.docker(
                    "exec",
                    runtime.names(run)[name],
                    "cat",
                    "/etc/ssh/ssh_host_ed25519_key.pub",
                ).stdout.split()[1]
                for name in ("app1", "app2", "app3")
            ]
            assert len(set(host_keys)) == 3, (
                "Managed targets must have distinct host keys"
            )
            log.append({"distinct_managed_host_keys": 3})
        if number == 48:
            # A long initial lease would bypass the renewal exercise. Probe
            # the actual issuer ACL inside this owned fixture, without logging
            # tokens or response bodies. The normal 60s issue is tested below.
            denied = runtime.exec(
                run,
                "source ~/quest/platform.env\n"
                "cat > /tmp/dq-invalid-issue.json <<'LEASE_PROBE'\n"
                '{"policies":["rail-reader"],"ttl":"600s","renewable":true,"explicit_max_ttl":"600s"}\n'
                "LEASE_PROBE\njq -e . /tmp/dq-invalid-issue.json >/dev/null\n"
                'status=$(curl -sS -o /dev/null -w "%{http_code}" -X POST '
                '-H "X-Vault-Token: $VAULT_MANAGER_TOKEN" '
                "-H 'Content-Type: application/json' --data-binary @/tmp/dq-invalid-issue.json "
                '"$VAULT_ADDR/v1/auth/token/create/rail-station")\n'
                'printf "%s\\n" "$status"\ntest "$status" = 403\n',
                check=False,
            )
            assert denied.returncode == 0, (
                "Overlong initial lease must be denied; HTTP " + denied.stdout.strip()
            )
            log.append({"issuer_denies_overlong_initial_ttl": True})
        if number == 99:
            denied = runtime.exec(
                run,
                "source ~/quest/platform.env\n"
                "cat > /tmp/invalid-rotation.json <<'ROTATION_PROBE'\n"
                '{"policies":["rail-reader"],"ttl":"600s","renewable":false,"explicit_max_ttl":"600s"}\n'
                "ROTATION_PROBE\n"
                'test "$(curl -sS -o /dev/null -w "%{http_code}" -X POST '
                '-H "X-Vault-Token: $VAULT_MANAGER_TOKEN" '
                "-H 'Content-Type: application/json' --data-binary @/tmp/invalid-rotation.json "
                '"$VAULT_ADDR/v1/auth/token/create/rail-rotation")" = 403\n'
                "printf '%s\\n' '{\"accessor\":\"foreign-accessor\"}' > /tmp/foreign-accessor.json\n"
                'test "$(curl -sS -o /dev/null -w "%{http_code}" -X POST '
                '-H "X-Vault-Token: $VAULT_MANAGER_TOKEN" '
                "-H 'Content-Type: application/json' --data-binary @/tmp/foreign-accessor.json "
                '"$VAULT_ADDR/v1/auth/token/revoke-accessor")" = 403\n'
                'test "$(curl -sS -o /dev/null -w "%{http_code}" '
                '-H "X-Vault-Token: $VAULT_MANAGER_TOKEN" '
                '"$VAULT_ADDR/v1/secret/data/dispatch")" = 403\n',
                check=False,
            )
            assert denied.returncode == 0, "Rotation issuer or revoker is too broad"
            log.append({"rotation_issuer_and_revoker_negative_probes": "PASS"})
        for stage in range(len(catalog.quests[number]["stages"])):
            setup = catalog.script(number, stage, "setup")
            result = runtime.exec(
                run, "set -euo pipefail\ncd ~/quest\n" + setup, timeout=240
            )
            facts = catalog.quests[number].get("immutable", {}).get(stage, [])
            if facts:
                runtime.capture_facts(dict(run, stage=stage), facts)
                for fact in facts:
                    denied = runtime.exec(
                        run,
                        f"printf tampered > /run/dq/facts/{stage}/{fact}",
                        check=False,
                    )
                    assert denied.returncode != 0, "Setup evidence must be read-only"
            log.append(
                {
                    "stage": stage,
                    "setup": "PASS",
                    "stdout": result.stdout,
                    "stderr": result.stderr,
                }
            )
            if number == 5:
                runtime.exec(run, "cd ~/quest\ntest ! -e prepare.yml && test -s rollout.yml")
                brief = catalog.text(5, "brief")["en"]
                consumer_commands = re.findall(r"^- `(.*)` —", brief, re.MULTILINE)
                assert len(consumer_commands) == 2
                denied = runtime.exec(
                    run, "cd ~/quest\n" + consumer_commands[0], check=False, timeout=60
                )
                assert denied.returncode != 0, "Private setup must reject the non-owner read"
                log.append({"preparation_playbook_removed": True, "non_owner_read_before": "DENIED"})
            check = catalog.script(number, stage, "check")
            if number == 66:
                # The old oracle accepted a fabricated missing digest without
                # deleting the real obsolete manifest. Working files are not
                # authoritative; only backend-frozen setup evidence is.
                runtime.exec(
                    run,
                    "cd ~/quest\npython3 - <<'POISON'\n"
                    "import json\nfrom pathlib import Path\n"
                    "c=json.loads(Path('/run/dq/facts/0/release-catalog.json').read_text())\n"
                    "c['obsolete']='sha256:'+'0'*64\n"
                    "Path('release-catalog.json').write_text(json.dumps(c))\n"
                    "Path('retention.json').write_text(json.dumps({'delete':[c['obsolete']]}))\n"
                    "POISON\n",
                )
                forged = runtime.exec(run, check, check=False)
                assert forged.returncode != 0, "Mutable catalog must not forge success"
                rejected = runtime.exec(run, "cd ~/quest; bash prune.sh", check=False)
                assert rejected.returncode != 0, (
                    "Prune must reject an unapproved digest"
                )
                log.append({"forged_retention_catalog_rejected": True})
            if number == 1 and stage == 0:
                from scripts.shell_trace_check import check as shell_trace_check

                log.append(
                    {
                        "shell_trace": asyncio.run(
                            shell_trace_check(runtime.names(run)["workstation"])
                        )
                    }
                )
            if number in {116, 117}:
                # The production poll reconciles the custom resource or stages
                # the static manifest before evaluating the first objectives.
                runtime.observe(run)
            if number in {121, 123}:
                runtime.game_controls(run)
            before = runtime.exec(run, check, check=False, timeout=40)
            assert before.returncode != 0, "Setup was already solved"
            objectives = catalog.quests[number]["stages"][stage]["objectives"]

            def goals(objectives=objectives):
                return [
                    runtime.exec(
                        run,
                        "set -euo pipefail\ncd ~/quest\n" + goal["check"],
                        check=False,
                        timeout=25,
                    ).returncode
                    for goal in objectives
                ]

            assert any(goals()), "Production objective checks were already solved"
            reference = (
                ROOT / "solutions" / f"{number:03}" / f"{stage}.sh"
            ).read_text()
            if number == 98:
                snapshot = runtime.kube(
                    "-n", runtime.namespace(run), "get", "pods,replicasets",
                    "-l", "app=board", "-o", "json",
                )
                items = json.loads(snapshot.stdout)["items"]
                old_pods = {item["metadata"]["uid"] for item in items if item["kind"] == "Pod"}
                old_sets = {item["metadata"]["uid"] for item in items if item["kind"] == "ReplicaSet"}
                assert old_pods and old_sets, "Missing original board rollout"
            stop = threading.Event()
            observation_errors = []

            def observer(stop=stop, errors=observation_errors):
                while not stop.wait(2.5):
                    try:
                        if number in {121, 123}:
                            runtime.game_controls(run)
                        else:
                            runtime.observe(run)
                    except (
                        RuntimeError,
                        OSError,
                        ValueError,
                        KeyError,
                        subprocess.SubprocessError,
                    ) as error:
                        errors.append(str(error))

            # The interactive Engine polls while a workstation command runs.
            # Preserve that phase for the transient server-owned eviction
            # condition, rather than inventing a post-deletion status fixture.
            thread = (
                threading.Thread(target=observer, daemon=True)
                if number in {77, 116, 117, 121, 123}
                else None
            )
            if thread:
                thread.start()
            try:
                fixed = runtime.exec(run, reference, timeout=240)
            finally:
                stop.set()
                if thread:
                    thread.join(timeout=10)
                    assert not thread.is_alive()
                    assert not observation_errors, observation_errors
            log.append(
                {
                    "stage": stage,
                    "before": "FAIL as expected",
                    "reference_stdout": fixed.stdout,
                    "reference_stderr": fixed.stderr,
                }
            )
            if number in {78, 93, 121, 123}:
                runtime.game_controls(run)
            if number in {75, 77, 116, 117}:
                runtime.observe(run)
            after = (
                wait_098_convergence(runtime, run, check, old_pods, old_sets)
                if number == 98
                else runtime.exec(run, check, check=False, timeout=60)
            )
            assert after.returncode == 0, after.stderr + "\n" + after.stdout
            assert not any(goals()), "Production objective checks did not pass"
            log[-1]["after"] = "PASS"
            if number == 15:
                # Reuse the unchanged learner playbook with a different data list.
                playbook_before = runtime.exec(run, 'cd ~/quest\nsha256sum rollout.yml').stdout
                runtime.exec(run, "cd ~/quest\nprintf '%s\\n' 'routes: [north, south, east, west]' > routes.yml")
                expanded_before = runtime.exec(run, check, check=False, timeout=25)
                assert expanded_before.returncode != 0, 'The added route was not checked'
                runtime.exec(run, 'cd ~/quest\nansible-playbook rollout.yml', timeout=120)
                expanded_after = runtime.exec(run, check, check=False, timeout=25)
                assert expanded_after.returncode == 0, expanded_after.stdout + expanded_after.stderr
                assert runtime.exec(run, 'cd ~/quest\nsha256sum rollout.yml').stdout == playbook_before
                assert not any(goals()), 'Expanded route list did not satisfy live objectives'
                log.append({'route_list_adaptation': {'added': 'west', 'before': 'FAIL as expected',
                                                    'after': 'PASS', 'unchanged_playbook': True}})
            if number == 5:
                identities = runtime.exec(
                    run,
                    "cd ~/quest\nansible fleet -i inventory.ini -m ansible.builtin.command "
                    "-a 'runuser -u nobody -- id -u'",
                    timeout=60,
                )
                uids = [int(line) for line in identities.stdout.splitlines() if line.isdigit()]
                assert len(uids) == 3 and all(uid != 0 for uid in uids)
                observations = []
                for command in consumer_commands:
                    observed = runtime.exec(run, "cd ~/quest\n" + command, timeout=60)
                    for host in ("app1", "app2", "app3"):
                        assert f"{host} |" in observed.stdout
                    observations.append({"command": command, "stdout": observed.stdout})
                assert observations[0]["stdout"].splitlines().count("north-ready") == 3
                log.append({"non_owner_uids": uids, "consumer_observations_after": observations})
        if number == 27:
            # Kubelet verifies credentials even for Never after a private pull.
            # The ordinary preloaded fixture must retain a distinct identity.
            public = {
                "apiVersion": "v1",
                "kind": "Pod",
                "metadata": {"name": "public-control"},
                "spec": {
                    "securityContext": {
                        "runAsNonRoot": True,
                        "runAsUser": 1000,
                        "seccompProfile": {"type": "RuntimeDefault"},
                    },
                    "containers": [
                        {
                            "name": "probe",
                            "image": runtime.images["app"],
                            "imagePullPolicy": "Never",
                            "command": ["sleep", "120"],
                            "resources": {
                                "requests": {"cpu": "10m", "memory": "8Mi"},
                                "limits": {"memory": "32Mi"},
                            },
                            "securityContext": {
                                "allowPrivilegeEscalation": False,
                                "capabilities": {"drop": ["ALL"]},
                            },
                        }
                    ],
                },
            }
            script = (
                "kubectl apply -f - <<'PUBLICCONTROL'\n"
                + json.dumps(public)
                + "\nPUBLICCONTROL\nkubectl wait --for=condition=Ready pod/public-control --timeout=60s\n"
            )
            runtime.exec(run, script, timeout=80)
            log.append({"public_image_after_private_pull": "PASS"})
    except Exception as error:
        log.append({"error": str(error)})
        try:
            log.append({"topology_at_failure": runtime.topology(run)})
            if "kubernetes" in runtime.dependencies(run):
                result = runtime.kube(
                    "-n",
                    runtime.namespace(run),
                    "get",
                    "events",
                    "--field-selector",
                    "type=Warning",
                    "-o",
                    "json",
                    check=False,
                )
                if result.returncode == 0:
                    log.append(
                        {
                            "warnings": [
                                {"reason": e.get("reason"), "message": e.get("message")}
                                for e in json.loads(result.stdout)["items"]
                            ]
                        }
                    )
                if "argocd" in runtime.dependencies(run):
                    result = runtime.kube(
                        "-n",
                        runtime.namespace(run),
                        "get",
                        "applications",
                        "-o",
                        "json",
                        check=False,
                    )
                    if result.returncode == 0:
                        log.append(
                            {
                                "applications": [
                                    x.get("status", {})
                                    for x in json.loads(result.stdout)["items"]
                                ]
                            }
                        )
        except (RuntimeError, OSError, ValueError) as diagnostic_error:
            log.append({"diagnostic_error": str(diagnostic_error)})
        raise
    finally:
        try:
            runtime.teardown(run)
            log.append({"teardown": "PASS"})
        except Exception as error:
            log.append({"teardown_error": str(error)})
            raise
        finally:
            (evidence / f"{number:03}.json").write_text(
                json.dumps(log, indent=2) + "\n"
            )
