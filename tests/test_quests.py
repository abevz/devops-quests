"""Real integration contract: same workstation exec path as interactive players."""

import asyncio
import hashlib
import json
import os
import secrets
import subprocess
import threading

import pytest

from devops_quests.catalog import RELEASED, ROOT, Catalog
from devops_quests.runtime import Runtime

pytestmark = pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1",
    reason="Explicit local sandbox opt-in required",
)


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
            after = runtime.exec(run, check, check=False, timeout=60)
            assert after.returncode == 0, after.stderr + "\n" + after.stdout
            assert not any(goals()), "Production objective checks did not pass"
            log[-1]["after"] = "PASS"
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
