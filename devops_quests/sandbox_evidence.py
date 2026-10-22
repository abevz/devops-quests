"""Bounded control input and backend observations unavailable for player edits."""

import json
import re
import secrets

CONTROL_READER = """import json, os, stat, sys
from pathlib import Path
try:
    fd=os.open(Path.home()/'quest'/sys.argv[1], os.O_RDONLY|os.O_NONBLOCK|os.O_NOFOLLOW)
except FileNotFoundError:
    sys.exit(1)
except OSError:
    print('null');sys.exit(0)
try:
    info=os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_size>4096:
        print('null');sys.exit(0)
    raw=os.read(fd,4097)
    if len(raw)>4096:
        print('null');sys.exit(0)
    try:
        print(json.dumps(json.loads(raw),ensure_ascii=True))
    except (ValueError,UnicodeError):
        print('null')
finally:
    os.close(fd)
"""


def record(runtime, run, name, data):
    if not re.fullmatch(r"[a-f0-9]{24}", run["id"]):
        raise ValueError("Invalid observation bay")
    if name not in {"webhook.json", "evictions.json", "static-pod.json"}:
        raise ValueError("Invalid observation name")
    folder = runtime.state / "bays" / run["id"] / "client" / "observations"
    folder.mkdir(mode=0o755, exist_ok=True)
    folder.chmod(0o755)
    path = folder / name
    content = json.dumps(data, sort_keys=True) + "\n"
    if path.exists() and path.read_text() == content:
        return
    temporary = folder / (name + "." + secrets.token_hex(8))
    temporary.write_text(content)
    temporary.chmod(0o444)
    temporary.replace(path)


def observe(runtime, run):
    """Read server-owned evidence only, on the ordinary objective-poll cadence."""
    if run["level"] == 75:
        result = runtime.kube(
            "-n",
            "dq-platform-" + run["id"],
            "logs",
            "deployment/argocd-server",
            "--tail=100",
            timeout=5,
            check=False,
        )
        repo = "http://gitea-" + run["id"] + ":3000/rail/station"
        message = (
            "Received push event repo: " + repo + ", revision: main, touchedHead: true"
        )
        accepted = False
        if result.returncode == 0:
            for line in result.stdout.splitlines():
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                if event.get("msg") == message and event.get("level") == "info":
                    accepted = True
        if accepted:
            record(
                runtime,
                run,
                "webhook.json",
                {
                    "repo": repo,
                    "branch": "main",
                    "authenticated": True,
                },
            )
    elif run["level"] == 77:
        initial = (
            runtime.state / "bays" / run["id"] / "client/facts/0/original-pod-uids.json"
        )
        if not initial.exists():
            return
        allowed = set(json.loads(initial.read_text()))
        result = runtime.kube(
            "-n",
            runtime.namespace(run),
            "get",
            "pods",
            "-l",
            "app=board",
            "-o",
            "json",
            timeout=5,
            check=False,
        )
        if result.returncode:
            return
        path = initial.parents[2] / "observations/evictions.json"
        seen = set(json.loads(path.read_text())) if path.exists() else set()
        for pod in json.loads(result.stdout)["items"]:
            uid = pod["metadata"]["uid"]
            if uid in allowed and any(
                c.get("type") == "DisruptionTarget"
                and c.get("status") == "True"
                and c.get("reason") == "EvictionByEvictionAPI"
                for c in pod.get("status", {}).get("conditions", [])
            ):
                seen.add(uid)
        if seen:
            record(runtime, run, "evictions.json", sorted(seen))
