"""Exercise the actual container boundary and authenticated terminal."""

import argparse
import asyncio
import fcntl
import json
import secrets
import socket
import threading
from pathlib import Path

from aiohttp import ClientSession, CookieJar, WSMsgType, WSServerHandshakeError, web

from devops_quests.catalog import ROOT, Catalog
from devops_quests.engine import Engine
from devops_quests.runtime import Runtime
from devops_quests.server import make_app
from devops_quests.store import Store


def isolated_profile(profile, state):
    """Refuse accidental reuse of the normal application profile or its DB."""
    profile = profile.resolve()
    state = state.resolve()
    database = profile / "progress.db"
    normal = state / "progress.db"
    if (
        profile == state
        or state in profile.parents
        or database.resolve() == normal.resolve()
        or (database.exists() and normal.exists() and database.samefile(normal))
    ):
        raise ValueError("Security checks require a separate synthetic profile")
    return profile


async def verify_pty(ws, marker, folder, timeout=10):
    """Observe the real container resize, which follows the local SIGWINCH."""
    output = ""

    async def prompt():
        nonlocal output
        chunk = ""
        while not chunk.endswith("$ "):
            message = await ws.receive()
            if message.type != WSMsgType.BINARY:
                raise RuntimeError("Terminal closed during PTY verification")
            chunk += message.data.decode(errors="replace")
            output += message.data.decode(errors="replace")
            await ws.send_json({"type": "ack", "bytes": len(message.data)})
        return chunk

    try:
        async with asyncio.timeout(timeout):
            await ws.send_json(
                {"type": "input", "data": "printf '\\n" + marker + "\\n'; id -u\r"}
            )
            authenticated = await prompt()
            assert marker in authenticated and "1000" in authenticated
            await ws.send_json({"type": "resize", "rows": 36, "cols": 120})
            for _ in range(40):
                await ws.send_json({"type": "input", "data": "stty size\r"})
                observed = await prompt()
                if "36 120" in observed.splitlines():
                    return
                await asyncio.sleep(0.05)
            raise TimeoutError("Container PTY resize was not observed")
    except TimeoutError:
        (folder / "pty-timeout.txt").write_text(output)
        raise


async def main(profile=None):
    runtime = Runtime(ROOT / ".state/runtime")
    profile = isolated_profile(
        profile or ROOT / ".state/security-profile", runtime.state
    )
    installation_lock = (runtime.state / "server.lock").open("a")
    try:
        fcntl.flock(installation_lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise RuntimeError(
            "Stop the app and other real sandbox tests before security checks"
        ) from None
    folder = ROOT / "artifacts/security"
    folder.mkdir(parents=True, exist_ok=True)
    store = Store(profile / "progress.db")
    pwfile = store.bootstrap()
    # A synthetic user database is separate from the normal app database.
    if not pwfile:
        pwfile = profile / "admin-password"
    engine = Engine(store, Catalog(), runtime)
    runner = web.AppRunner(make_app(store, engine.catalog, engine, base="/devops/"))
    await runner.setup()
    site = web.TCPSite(runner, "127.0.0.1", 8767)
    await site.start()
    proof = {}
    run = None
    docker_run = None
    listener = None
    try:
        async with ClientSession(cookie_jar=CookieJar(unsafe=True)) as client:
            base = "http://127.0.0.1:8767/devops/api/"
            origin = "http://127.0.0.1:8767"
            async with client.get(base + "state") as response:
                proof["anonymous_state"] = response.status
            try:
                await client.ws_connect(base + "terminal", headers={"Origin": origin})
            except WSServerHandshakeError as error:
                proof["anonymous_ws"] = error.status
            async with client.post(
                base + "login",
                json={"name": "admin", "password": pwfile.read_text().strip()},
                headers={"Origin": origin},
            ) as response:
                assert response.status == 200
            async with client.get(base + "state") as response:
                data = await response.json()
            headers = {"Origin": origin, "X-CSRF-Token": data["csrf"]}
            async with client.post(
                base + "start", json={"level": 1}, headers=headers
            ) as response:
                assert response.status == 200, await response.text()
                run = await response.json()
            student = "reader-" + secrets.token_hex(3)
            student_password = secrets.token_urlsafe(18)
            async with client.post(
                base + "users",
                json={"name": student, "password": student_password},
                headers=headers,
            ) as response:
                assert response.status == 200
            async with ClientSession(cookie_jar=CookieJar(unsafe=True)) as other:
                async with other.post(
                    base + "login",
                    json={"name": student, "password": student_password},
                    headers={"Origin": origin},
                ) as response:
                    assert response.status == 200
                async with other.get(base + "state") as response:
                    other_state = await response.json()
                assert other_state["run"] is None and other_state["progress"] == []
                async with other.post(
                    base + "check",
                    json={},
                    headers={"Origin": origin, "X-CSRF-Token": other_state["csrf"]},
                ) as response:
                    assert response.status == 400
                try:
                    await other.ws_connect(
                        base + "terminal", headers={"Origin": origin}
                    )
                except WSServerHandshakeError as error:
                    assert error.status == 400
                else:
                    raise AssertionError("A second user opened another user's terminal")
            proof["cross_user_run_and_terminal_isolation"] = True
            try:
                await client.ws_connect(
                    base + "terminal", headers={"Origin": "http://evil.invalid"}
                )
            except WSServerHandshakeError as error:
                proof["wrong_origin_ws"] = error.status
            async with client.ws_connect(
                base + "terminal", headers={"Origin": origin}
            ) as ws:
                tabs = [
                    await client.ws_connect(
                        base + "terminal", headers={"Origin": origin}
                    )
                    for _ in range(2)
                ]
                try:
                    await client.ws_connect(
                        base + "terminal", headers={"Origin": origin}
                    )
                except WSServerHandshakeError as error:
                    assert error.status == 429
                    proof["fourth_terminal_rejected"] = error.status
                else:
                    raise AssertionError("Fourth terminal was accepted")
                # Wait for the real interactive shell; Docker exec and bashrc
                # completion setup may finish after the WebSocket upgrade.
                for terminal in [ws, *tabs]:
                    ready = bytearray()
                    async with asyncio.timeout(20):
                        while not ready.endswith(b"$ "):
                            message = await terminal.receive()
                            if message.type == WSMsgType.BINARY:
                                ready.extend(message.data)
                                await terminal.send_json(
                                    {"type": "ack", "bytes": len(message.data)}
                                )
                            else:
                                raise RuntimeError(
                                    "Terminal closed before its shell prompt"
                                )
                for tab in tabs:
                    await tab.send_json({"type": "close"})
                    await tab.close()
                marker = "DQ_PTY_" + secrets.token_hex(5)
                await verify_pty(ws, marker, folder)
                proof["authenticated_pty_nonroot"] = True
                proof["pty_resize"] = True
            check = """set -euo pipefail
! test -S /var/run/docker.sock
! test -e /root/.kube/config
! test -e /home/hacker/.kube/config
! test -e /run/secrets
kubectl get namespaces >/dev/null
! kubectl get nodes >/dev/null 2>&1
! kubectl get pods --all-namespaces >/dev/null 2>&1
! kubectl -n kube-system get secrets >/dev/null 2>&1
! kubectl auth can-i create clusterrolebindings | grep -qx yes
python3 - <<'PYINNER'
import socket
for host,port in [('1.1.1.1',443),('192.0.2.1',80)]:
 try:
  c=socket.create_connection((host,port),timeout=1);c.close()
 except OSError:continue
 raise RuntimeError('External TCP connection unexpectedly worked')
PYINNER
"""
            result = await asyncio.to_thread(runtime.exec, run, check, timeout=30)
            proof["paths_rbac_external_tcp"] = "PASS"
            mounts = runtime.inspect(runtime.names(run)["workstation"])["Mounts"]
            assert not any(
                m["Destination"]
                in {
                    "/var/run/docker.sock",
                    "/root/.ssh",
                    "/root/.kube",
                    "/var/lib/syntax-quest",
                }
                for m in mounts
            )
            proof["mount_allowlist"] = "PASS"
            dns = "python3 - <<'DNSCHECK'\nimport socket\nsocket.setdefaulttimeout(3)\ntry: socket.getaddrinfo('example.com',443)\nexcept OSError: pass\nelse: raise RuntimeError('External DNS unexpectedly available')\nDNSCHECK"
            await asyncio.to_thread(runtime.exec, run, dns, timeout=15)
            proof["external_dns_blocked"] = True
            # A live host listener is a stronger host-access test than a closed port.
            net = json.loads(
                runtime.docker("network", "inspect", runtime.network).stdout
            )[0]
            gateway = net["IPAM"]["Config"][0]["Gateway"]
            listener = socket.socket()
            listener.bind((gateway, 0))
            listener.listen(1)
            port = listener.getsockname()[1]
            hostcheck = (
                "python3 - <<'PYINNER'\nimport socket\ntry:\n c=socket.create_connection(("
                + repr(gateway)
                + ","
                + str(port)
                + "),timeout=2)\nexcept OSError:pass\nelse:raise RuntimeError('Host listener reachable')\nPYINNER"
            )
            await asyncio.to_thread(runtime.exec, run, hostcheck)
            proof["live_host_listener_blocked"] = True
            # PSA rejection is verified against the API, not inferred from YAML.
            bad = {
                "apiVersion": "v1",
                "kind": "Pod",
                "metadata": {"name": "escape-probe"},
                "spec": {
                    "serviceAccountName": "player",
                    "hostNetwork": True,
                    "containers": [
                        {
                            "name": "escape",
                            "image": runtime.images["app"],
                            "securityContext": {"privileged": True},
                        }
                    ],
                },
            }
            script = "kubectl create -f - <<'BADPOD'\n" + json.dumps(bad) + "\nBADPOD\n"
            result = await asyncio.to_thread(runtime.exec, run, script, check=False)
            assert result.returncode != 0 and "violates PodSecurity" in result.stderr, (
                result.returncode,
                result.stdout,
                result.stderr,
            )
            proof["privileged_hostnetwork_rejected"] = True
            assert proof["anonymous_ws"] == 401 and proof["wrong_origin_ws"] == 403
    finally:
        if listener:
            listener.close()
        (folder / "result.json").write_text(json.dumps(proof, indent=2) + "\n")
        if run:
            current = store.run(run["id"], run["user_id"])
            store.update(current, status="reset", ended=store.clock())
            await asyncio.to_thread(runtime.teardown, run)
        await runner.cleanup()
    try:
        # Even a privileged child of the learner's Docker daemon must remain
        # inside RootlessKit's user namespace, without usable host block devices.
        docker_run = {"id": secrets.token_hex(12), "level": 3}
        await asyncio.to_thread(runtime.create, docker_run)
        versions = await asyncio.to_thread(
            runtime.exec,
            docker_run,
            "bash --version | head -n 1; kubectl version --client=true; helm version --short; ansible --version | head -n 1; tofu version | head -n 1; jq --version",
        )
        proof["workstation_versions"] = versions.stdout.strip()
        script = """set -euo pipefail
docker info --format '{{json .SecurityOptions}}' | grep -q rootless
docker run --rm --privileged "$DQ_APP_IMAGE" sh -c '
  cat /proc/self/uid_map
  count=0
  for device in /dev/*; do
    [ -b "$device" ] || continue
    if (: < "$device") 2>/dev/null; then count=$((count + 1)); fi
  done
  printf "openable-block-devices: %s\n" "$count"
  test "$count" -eq 0
  ! test -S /var/run/docker.sock
'
"""
        result = await asyncio.to_thread(runtime.exec, docker_run, script, timeout=60)
        uid_map = result.stdout.split("openable-block-devices:")[0].strip()
        assert uid_map.split()[:3] == ["0", "1000", "1"], uid_map
        proof["nested_docker_rootless"] = True
        proof["nested_privileged_uid_map"] = uid_map
        proof["nested_privileged_openable_host_block_devices"] = 0
        net = json.loads(runtime.docker("network", "inspect", runtime.network).stdout)[
            0
        ]
        proof["game_network_ipv6_enabled"] = net["EnableIPv6"]
        assert not net["EnableIPv6"]
        gateway = net["IPAM"]["Config"][0]["Gateway"]
        listener = socket.socket()
        listener.bind((gateway, 0))
        listener.listen(1)
        port = listener.getsockname()[1]

        def close_connections():
            while True:
                try:
                    connection, _ = listener.accept()
                    connection.close()
                except OSError:
                    return

        threading.Thread(target=close_connections, daemon=True).start()
        with socket.create_connection((gateway, port), timeout=2) as positive:
            assert positive.recv(1) == b""
        script = (
            'docker run --rm --privileged --network host "$DQ_APP_IMAGE" sh -c '
            + "'command -v nc >/dev/null && command -v timeout >/dev/null || exit 2; if timeout 2 nc "
            + gateway
            + " "
            + str(port)
            + " </dev/null >/dev/null 2>&1; then echo Host-listener-reachable >&2; exit 1; fi'"
        )
        await asyncio.to_thread(runtime.exec, docker_run, script, timeout=15)
        proof["nested_privileged_live_host_listener_blocked"] = True
    finally:
        if listener:
            listener.close()
        if docker_run:
            await asyncio.to_thread(runtime.teardown, docker_run)
        (folder / "result.json").write_text(json.dumps(proof, indent=2) + "\n")
    print(json.dumps(proof))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", type=Path)
    asyncio.run(main(parser.parse_args().profile))
