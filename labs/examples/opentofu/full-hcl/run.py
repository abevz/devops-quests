import json
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent
GROUP = "terraform-2"
results = []


def call(path, verb, *args, expected=0):
    p = subprocess.run(
        ["tofu", verb, "-no-color", *args],
        cwd=path,
        check=False,
        capture_output=True,
        text=True,
        timeout=60,
    )
    with (path / "result.log").open("a") as log:
        log.write(
            "$ tofu " + verb + " " + " ".join(args) + "\n" + p.stdout + p.stderr + "\n"
        )
    if p.returncode != expected:
        raise AssertionError(
            f"{verb}: expected {expected}, got {p.returncode}\n{p.stdout}{p.stderr}"
        )
    return p.stdout + p.stderr


def plan(path, *args):
    call(path, "plan", "-out=case.tfplan", *args)
    p = subprocess.run(
        ["tofu", "show", "-json", "case.tfplan"],
        cwd=path,
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(p.stdout)


for case in json.loads((root / "cases.json").read_text()):
    path = root / case["directory"]
    n = case["block"]
    text = (path / "main.tf").read_text()
    passed = False
    try:
        call(path, "init", "-input=false")
        call(path, "validate")
        # Every standalone source configuration is parsed, planned and evaluated.
        # Explicitly negative provisioners return an error after creating state.
        failed = GROUP == "terraform-6" and n in [24, 26]
        output = call(
            path, "apply", "-auto-approve", "-input=false", expected=1 if failed else 0
        )
        if failed:
            assert "local-exec provisioner error" in output
            p = plan(path)
            assert any(
                "delete" in c["change"]["actions"] for c in p["resource_changes"]
            )
        elif GROUP == "terraform-6":
            if n in [3, 5]:
                p = plan(path, "-var=release=v2")
                assert any(
                    c["change"]["actions"] == ["create", "delete"]
                    for c in p["resource_changes"]
                )
            elif n in [6, 8, 31]:
                output = call(path, "plan", "-var=release=v2", expected=1)
                assert "cannot be destroyed" in output
            elif n == 9:
                call(path, "plan", "-detailed-exitcode", "-var=release=v2")
            elif n in [15, 17]:
                assert (
                    "precondition"
                    in call(path, "plan", "-var=port=0", expected=1).lower()
                )
                if n == 17:
                    assert (
                        "postcondition"
                        in call(
                            path,
                            "apply",
                            "-auto-approve",
                            "-var=port=70000",
                            expected=1,
                        ).lower()
                    )
            elif n in [18, 20]:
                assert "Check block assertion failed" in output
            elif n in [21, 23]:
                p = plan(path, "-var=release=v2")
                assert any(
                    "delete" in c["change"]["actions"] for c in p["resource_changes"]
                )
            elif n in [1, 28]:
                p = plan(path, "-var=release=v2")
                assert any(
                    c["change"]["actions"] == ["update"] for c in p["resource_changes"]
                )
        elif GROUP == "terraform-2":
            if n == 5:
                call(path, "plan", "-var=environment=production", expected=1)
            if n == 8:
                call(path, "plan", "-var=listen_port=2048.5", expected=1)
        passed = True
    except (
        RuntimeError,
        AssertionError,
        KeyError,
        ValueError,
        subprocess.SubprocessError,
        OSError,
    ) as e:
        print(case["directory"], "FAIL", str(e), flush=True)
    results.append(dict(case, passed=passed))
    print(case["directory"], "PASS" if passed else "FAIL", flush=True)
(root / "results.json").write_text(json.dumps(results, indent=2))
if not all(r["passed"] for r in results):
    sys.exit(1)
