"""Opt-in real workstation editor and terminal lifecycle checks; no kind needed."""

import asyncio
import json
import os
import secrets
import subprocess

import pytest
from aiohttp import WSMsgType
from aiohttp.test_utils import TestClient

from devops_quests import terminal
from devops_quests.server import COOKIE
from scripts.editor_pty_check import check, check_unicode_shell
from scripts.terminal_benchmark import ProductionTestServer, fixture

pytestmark = pytest.mark.skipif(
    os.environ.get("DQ_TERMINAL_INTEGRATION") != "1",
    reason="Explicit disposable Docker fixture opt-in required",
)


@pytest.fixture
def workstation():
    name = "dq-terminal-check-" + secrets.token_hex(6)
    docker = ["docker", "--host", "unix:///var/run/docker.sock"]
    subprocess.run(
        [
            *docker,
            "run",
            "--pull",
            "never",
            "-d",
            "--name",
            name,
            "--label",
            "dq-terminal-check=true",
            "--network",
            "none",
            "--memory",
            "256m",
            "--cpus",
            "0.5",
            "--entrypoint",
            "sleep",
            "devops-quests/workstation:0.1.0",
            "infinity",
        ],
        capture_output=True,
        check=True,
    )
    try:
        yield name
    finally:
        subprocess.run([*docker, "rm", "-f", name], check=True, capture_output=True)


def test_real_vim_keys_and_unicode_shell(workstation):
    check_unicode_shell(workstation)
    check(workstation)


async def test_closing_tab_ends_remote_session_children_and_preserves_other(
    workstation, tmp_path, monkeypatch
):
    cleanup_events = []
    original_end = terminal.end_shell

    def end(name, identity):
        cleanup_events.append((identity, "started"))
        original_end(name, identity)
        cleanup_events.append((identity, "ended"))

    monkeypatch.setattr(terminal, "end_shell", end)
    app, token = fixture(workstation, tmp_path)
    client = TestClient(ProductionTestServer(app))
    await client.start_server()

    async def connect():
        return await client.ws_connect(
            "/api/terminal",
            headers={
                "Origin": str(client.make_url("/")).rstrip("/"),
                "Cookie": f"{COOKIE}={token}",
            },
        )

    async def read_until(ws, marker):
        data = bytearray()
        async with asyncio.timeout(10):
            while marker not in data:
                message = await ws.receive()
                assert message.type == WSMsgType.BINARY
                data.extend(message.data)
                await ws.send_json({"type": "ack", "bytes": len(message.data)})
        return data

    def tagged_sessions():
        code = """import os,json
from pathlib import Path
found={}
for p in Path('/proc').iterdir():
 if not p.name.isdigit():continue
 try:
  for entry in (p/'environ').read_bytes().split(b'\\0'):
   if entry.startswith(b'DQ_TERMINAL_ID='):found.setdefault(entry.decode().split('=',1)[1],[]).append(int(p.name))
 except OSError:pass
print(json.dumps(found))"""
        data = subprocess.check_output(
            [
                "docker",
                "--host",
                "unix:///var/run/docker.sock",
                "exec",
                "--user",
                "1000:1000",
                workstation,
                "python3",
                "-c",
                code,
            ]
        )
        return json.loads(data)

    sockets = []
    try:
        sockets = [await connect() for _ in range(3)]
        for ws in sockets:
            await read_until(ws, b"$ ")
        first = await asyncio.to_thread(tagged_sessions)
        assert len(first) == 3
        # A foreground job has a different process group but the same session.
        await sockets[0].send_json({"type": "input", "data": "sleep 600\r"})
        await asyncio.sleep(0.1)
        await sockets.pop(0).close()
        for _ in range(50):
            remaining = await asyncio.to_thread(tagged_sessions)
            if len(remaining) == 2:
                break
            await asyncio.sleep(0.05)
        assert len(remaining) == 2 and set(remaining) < set(first), cleanup_events
        for ws in sockets:
            await ws.send_json(
                {"type": "input", "data": "printf 'STILL_%s\\n' ALIVE\r"}
            )
            await read_until(ws, b"STILL_ALIVE")
        for ws in sockets:
            await ws.close()
        sockets = []
        for _ in range(50):
            remaining = await asyncio.to_thread(tagged_sessions)
            if not remaining:
                break
            await asyncio.sleep(0.05)
        assert not remaining
        await asyncio.to_thread(
            subprocess.run,
            ["docker", "exec", workstation, "kill", "-0", "1"],
            check=True,
        )
    finally:
        for ws in sockets:
            await ws.close()
        await client.close()
