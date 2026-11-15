"""Real old-minimum rejection and bounded production consumer/caller observations."""

import hashlib
import json
import os
import secrets
import shlex
from pathlib import Path

import pytest

from devops_quests.catalog import ROOT, Catalog
from devops_quests.runtime import Runtime


@pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1", reason="Explicit real sandbox opt-in"
)
@pytest.mark.parametrize("number", [52, 63, 69, 74])
def test_native_ansible_consumer_shortcuts(number, tmp_path):
    catalog = Catalog()
    runtime = Runtime(ROOT / ".state/runtime")
    run = {"id": secrets.token_hex(12), "level": number}
    folder = Path(os.environ.get("DQ_EVIDENCE_DIR", str(tmp_path)))
    folder.mkdir(parents=True, exist_ok=True)
    frozen = ROOT / "tests/fixtures/deepen-ansible-consumers"
    record = {
        "quest": number,
        "commands": [],
        "sources": {
            str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for base in (ROOT / f"quests/{number:03}", ROOT / f"solutions/{number:03}")
            for p in base.rglob("*")
            if p.is_file()
        },
    }

    def execute(script, expected=0):
        result = runtime.exec(
            run, "set -euo pipefail\ncd ~/quest\n" + script, check=False, timeout=180
        )
        record["commands"].append(
            {
                "script": script,
                "exit": result.returncode,
                "stdout": result.stdout,
                "stderr": result.stderr,
            }
        )
        assert result.returncode == expected, result.stdout + result.stderr
        return result

    try:
        runtime.create(run)
        execute(
            'deadline=$((SECONDS+10))\nfor host in app1 app2 app3; do\n until ssh -n -o BatchMode=yes -o ConnectTimeout=1 -o ConnectionAttempts=1 -p 2222 root@"$host-${DQ_NAMESPACE#dq-}" true 2>/dev/null; do\n  [ "$SECONDS" -lt "$deadline" ] || exit 1\n  sleep 0.2\n done\ndone'
        )
        execute(catalog.script(number, 0, "setup"))
        runtime.capture_facts(
            dict(run, stage=0), catalog.quests[number].get("immutable", {}).get(0, [])
        )
        for goal in catalog.quests[number]["stages"][0]["objectives"]:
            if goal.get("keep"):
                execute(goal["check"])
        current = catalog.script(number, 0, "check")
        execute(current, 1)
        if number == 52:
            for host in ("app1", "app2", "app3"):
                execute(
                    "ssh -n -o BatchMode=yes -p 2222 root@"
                    + host
                    + '-"${DQ_NAMESPACE#dq-}" '
                    + shlex.quote(
                        "grep -q PermissionError /var/log/quest-banner-reader.log"
                    )
                )
        if number == 74:
            # The old minimum assumed its complete starting program was handed over.
            execute((frozen / "074-setup.sh").read_text())
        execute((frozen / f"{number:03}.sh").read_text())
        execute((frozen / f"{number:03}-legacy-check.sh").read_text())
        markers = {
            52: "consumer_cache",
            63: "recovery_branches",
            69: "credential_access",
            74: "preview_effects",
        }
        failure = execute(current, 1)
        assert "[DQ:" + markers[number] + "]" in failure.stdout
        if number == 52:
            execute(
                'ansible fleet -m ansible.builtin.file -a "path=/srv/site/message mode=0600"'
            )
        if number == 74:
            for host in ("app1", "app2", "app3"):
                execute(
                    "ssh -n -o BatchMode=yes -p 2222 root@"
                    + host
                    + '-"${DQ_NAMESPACE#dq-}" '
                    + shlex.quote(
                        'printf "%s\\n" previous-74 > /srv/site/message; dq-service reload'
                    )
                )
        execute((ROOT / f"solutions/{number:03}/0.sh").read_text())
        execute(current)
        if number == 69:
            execute(
                "ansible fleet -m ansible.builtin.file -a 'path=/srv/relay/station-token owner=root group=credential-b mode=0640'"
            )
            execute(current)
            execute("printf '# changed source\\n' >> credentials.yml")
            execute((frozen / "069-legacy-check.sh").read_text())
            failure = execute(current, 1)
            assert "[DQ:credential_original]" in failure.stdout
            execute("cp /run/dq/facts/0/credentials.yml credentials.yml")
            execute(current)
            execute(
                "ansible fleet -m ansible.builtin.file -a 'path=/srv/relay/station-token mode=0622'"
            )
            failure = execute(current, 1)
            assert "[DQ:credential_access]" in failure.stdout
        if number == 74:
            execute(
                "python3 -I - <<'UNSAFE'\nfrom pathlib import Path\nimport yaml\np=Path('rollout.yml');play=yaml.safe_load(p.read_text());play[0]['handlers'][0]['check_mode']=False;p.write_text(yaml.safe_dump(play,sort_keys=False))\nUNSAFE"
            )
            execute((frozen / "074-legacy-check.sh").read_text())
            failure = execute(current, 1)
            assert "[DQ:preview_effects]" in failure.stdout
        record["result"] = "PASS"
    except BaseException as error:
        record["error"] = repr(error)
        raise
    finally:
        try:
            runtime.teardown(run)
            record["teardown"] = "PASS"
        finally:
            (folder / f"{number:03}-consumers-native.json").write_text(
                json.dumps(record, indent=2) + "\n"
            )


def replay_program(number):
    import ast
    import yaml

    check = yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())[
        "stages"
    ][0]["objectives"][1]["check"]
    wrapper = check.split("<<'DQ_CALLER_CAPABILITY'\n", 1)[1].split(
        "\nDQ_CALLER_CAPABILITY", 1
    )[0]
    tree = ast.parse(wrapper)
    call = next(
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "run"
    )
    return wrapper, ast.literal_eval(call.args[0].elts[-1])


@pytest.mark.parametrize("number", [63, 74])
@pytest.mark.parametrize(
    "variant",
    [
        "valid",
        "wrong-cache",
        "lost-control",
        "preview-mutation",
        "untrusted-mutation",
        "failed-cli",
    ],
)
def test_shipped_replays_observe_effects(
    number, variant, tmp_path, monkeypatch, capsys
):
    import subprocess
    from types import SimpleNamespace

    monkeypatch.chdir(tmp_path)
    if number == 63:
        (tmp_path / "previous.txt").write_text("original backup\n")
        (tmp_path / "previous.sha256").write_text("original receipt\n")
    original_read = Path.read_bytes

    def read(path):
        if str(path).startswith("/run/dq/facts/0/"):
            return (tmp_path / path.name).read_bytes()
        return original_read(path)

    monkeypatch.setattr(Path, "read_bytes", read)
    calls = []

    def cli(args, **kwargs):
        assert 0 < kwargs["timeout"] <= 14
        assert "private-input-sentinel" not in " ".join(args)
        inputs = json.loads(args[args.index("-e") + 1])
        live = Path(inputs["delivery_path"])
        cache = Path(inputs["service_reload"][-1])
        control = live.parent / ("unrelated" if number == 63 else "unrelated-data")
        calls.append(args)
        changed, skipped, rescued = 1, 0, 0
        if variant == "failed-cli":
            return SimpleNamespace(
                returncode=2,
                stdout="private-input-sentinel",
                stderr="private-input-sentinel",
            )
        if number == 63:
            backup = Path(inputs["previous_path"])
            incoming = Path(inputs["candidate_path"])
            untrusted = (
                hashlib.sha256(backup.read_bytes()).hexdigest()
                != inputs["previous_sha256"]
            )
            if untrusted:
                if variant == "untrusted-mutation":
                    live.write_text("unauthorized change")
                return SimpleNamespace(
                    returncode=2, stdout="private-input-sentinel", stderr=""
                )
            accepted = incoming.read_text().strip() == "approved"
            live.write_bytes(incoming.read_bytes() if accepted else backup.read_bytes())
            cache.write_bytes(live.read_bytes())
            Path(inputs["recovery_marker"]).write_text("checked\n")
            rescued = int(not accepted)
        else:
            preview = "--check" in args
            changed = int(live.read_text().strip() != inputs["release_text"])
            skipped = int(preview)
            if not preview:
                live.write_text(inputs["release_text"] + "\n")
                cache.write_bytes(live.read_bytes())
            elif variant == "preview-mutation":
                cache.write_text("mutated during preview\n")
        if variant == "wrong-cache":
            cache.write_text("stale\n")
        if variant == "lost-control":
            control.unlink(missing_ok=True)
        output = f"PLAY RECAP\nprobe : ok=4 changed={changed} unreachable=0 failed=0 skipped={skipped} rescued={rescued} ignored=0\n"
        return SimpleNamespace(returncode=0, stdout=output, stderr="")

    monkeypatch.setattr(subprocess, "run", cli)
    _, program = replay_program(number)
    with pytest.raises((SystemExit, OSError)) as result:
        exec(compile(program, "shipped-caller-effects", "exec"), {})
    allowed = (
        variant == "valid"
        or (number == 63 and variant == "preview-mutation")
        or (number == 74 and variant == "untrusted-mutation")
    )
    assert (isinstance(result.value, SystemExit) and result.value.code == 0) is allowed
    assert calls
    assert "private-input-sentinel" not in capsys.readouterr().out


@pytest.mark.parametrize("number", [63, 74])
@pytest.mark.parametrize(
    "variant", ["timeout", "unclassified-failure", "classified-failure"]
)
def test_caller_wrapper_bounds_and_redacts(number, variant, monkeypatch, capsys):
    import subprocess
    from types import SimpleNamespace

    def cli(args, **kwargs):
        assert kwargs["timeout"] == 14
        if variant == "timeout":
            raise subprocess.TimeoutExpired(args, 14, output="private-input-sentinel")
        return SimpleNamespace(
            returncode=1,
            stdout=(
                "Original input: ✗ [DQ:caller_original]\n"
                if variant == "classified-failure"
                else "private-input-sentinel"
            ),
            stderr="private-input-sentinel",
        )

    monkeypatch.setattr(subprocess, "run", cli)
    wrapper, _ = replay_program(number)
    with pytest.raises(SystemExit) as result:
        exec(compile(wrapper, "shipped-caller-wrapper", "exec"), {})
    assert result.value.code != 0
    output = capsys.readouterr().out
    assert "private-input-sentinel" not in output
    assert "[DQ:caller_" in output


@pytest.mark.parametrize(
    "number,index,marker", [(52, 2, "DQ_CONSUMERS"), (69, 1, "DQ_CREDENTIAL_CONSUMERS")]
)
def test_nested_remote_observers_compile(number, index, marker):
    import ast
    import yaml

    check = yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())[
        "stages"
    ][0]["objectives"][index]["check"]
    code = check.split("<<'" + marker + "'\n", 1)[1].split("\n" + marker, 1)[0]
    tree = ast.parse(code)
    for node in tree.body:
        if (
            isinstance(node, ast.Assign)
            and isinstance(node.targets[0], ast.Name)
            and node.targets[0].id in {"observer", "access"}
        ):
            compile(ast.literal_eval(node.value), "provided-remote-observer", "exec")
