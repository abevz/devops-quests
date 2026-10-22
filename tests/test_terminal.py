"""Real local PTYs at the authenticated WS seam; no Docker or player data."""

import asyncio
import os
import subprocess
import sys
import threading
from pathlib import Path
from types import SimpleNamespace

import pytest
from aiohttp import WSMsgType, WSServerHandshakeError
from aiohttp.test_utils import TestClient

from devops_quests import terminal
from devops_quests.catalog import Catalog
from devops_quests.engine import Engine
from devops_quests.server import COOKIE, make_app
from devops_quests.store import Store
from scripts.terminal_benchmark import ProductionTestServer


@pytest.fixture
async def shell(tmp_path, monkeypatch):
    store = Store(tmp_path / "profile.db")
    token = store.login("admin", store.bootstrap().read_text().strip(), "fixture")
    user = store.session(token)["user_id"]
    run = store.create_run(user, 1, "normal")
    original = asyncio.create_subprocess_exec

    # Real Bash + the production prompt hook and FIFO reader, replacing only
    # Docker transport. Each test has a private HOME and channel directory.
    rc = tmp_path / "bashrc"
    rc.write_text(
        "PS1='fixture$ '\nsource "
        + str(Path(__file__).resolve().parents[1] / "images/command-trace.bash")
        + "\n"
    )
    channels = set()

    async def spawn_shell(*args, **kwargs):
        assert "1000:1000" in args
        identity = next(
            x.split("=", 1)[1] for x in args if x.startswith("DQ_TERMINAL_ID=")
        )
        env = dict(
            os.environ,
            HOME=str(tmp_path),
            DQ_TRACE_DIRECTORY=str(tmp_path),
            DQ_TERMINAL_ID=identity,
            TERM="xterm-256color",
        )
        channels.add(identity)
        if args[-2:] == ("/bin/bash", "-il"):
            assert "TERM=xterm-256color" in args
            return await original(
                "/bin/bash", "--noprofile", "--rcfile", str(rc), "-i", env=env, **kwargs
            )
        assert args[args.index("fixture") + 1] == "python3"
        assert terminal.HISTORY_READER in args
        env["DQ_TRACE_READER"] = "1"
        return await original(
            sys.executable,
            "-u",
            "-c",
            terminal.HISTORY_READER,
            identity,
            env=env,
            **kwargs,
        )

    monkeypatch.setattr(terminal.asyncio, "create_subprocess_exec", spawn_shell)
    monkeypatch.setattr(
        terminal,
        "end_shell",
        lambda _name, identity: subprocess.run(
            [sys.executable, "-c", terminal.END_SHELL, identity],
            check=True,
            capture_output=True,
        ),
    )
    monkeypatch.setattr(terminal, "SESSION_INTERVAL", 0.08)
    monkeypatch.setattr(terminal, "ACTIVITY_INTERVAL", 0.15)

    class FixtureEngine(Engine):
        async def background(self):
            await asyncio.Event().wait()

    engine = FixtureEngine(
        store,
        Catalog(),
        SimpleNamespace(
            names=lambda r: {"workstation": "fixture"},
            owned=lambda name: True,
            teardown=lambda r: None,
        ),
    )
    hubs = []
    initialize = terminal.TerminalHub.__init__

    def track_hub(hub, *args, **kwargs):
        initialize(hub, *args, **kwargs)
        hubs.append(hub)

    monkeypatch.setattr(terminal.TerminalHub, "__init__", track_hub)
    client = TestClient(ProductionTestServer(make_app(store, Catalog(), engine)))
    await client.start_server()

    async def connect(token=token, origin=None):
        return await client.ws_connect(
            "/api/terminal",
            headers={
                "Origin": origin or str(client.make_url("/")).rstrip("/"),
                "Cookie": f"{COOKIE}={token}",
            },
        )

    async def wait_slots(expected):
        async with asyncio.timeout(3):
            while sum(len(slots) for slots in hubs[0].connections.values()) != expected:
                await asyncio.sleep(0.01)

    try:
        yield SimpleNamespace(
            store=store,
            token=token,
            run=run,
            connect=connect,
            engine=engine,
            wait_slots=wait_slots,
        )
    finally:
        await client.close()
        for identity in channels:
            (tmp_path / ("dq-trace-" + identity)).unlink(missing_ok=True)


async def output_until(ws, marker):
    data = bytearray()
    async with asyncio.timeout(10):
        while marker not in data:
            message = await ws.receive()
            assert message.type == WSMsgType.BINARY, message
            data.extend(message.data)
            await ws.send_json({"type": "ack", "bytes": len(message.data)})
    return bytes(data)


async def input_text(ws, text):
    await ws.send_json({"type": "input", "data": text})


async def test_three_independent_shells_limit_and_command_trace(shell):
    sockets = [await shell.connect() for _ in range(3)]
    try:
        other_login = shell.store.login(
            "admin",
            (shell.store.path.parent / "admin-password").read_text().strip(),
            "other-browser",
        )
        with pytest.raises(WSServerHandshakeError) as fourth:
            await shell.connect(token=other_login)
        assert fourth.value.status == 429
        for i, ws in enumerate(sockets):
            await input_text(
                ws,
                f"export TAB_VALUE=tab{i}; printf '\\n'; cat /dev/null; echo TRACE{i}:$TAB_VALUE\r",
            )
            data = await output_until(ws, f"TRACE{i}:tab{i}".encode())
            assert f"TRACE{(i + 1) % 3}:tab".encode() not in data
        await asyncio.sleep(0.3)
        run = shell.store.run(shell.run["id"], shell.run["user_id"])
        assert all(any(f"TRACE{i}" in cmd for cmd in run["commands"]) for i in range(3))
        await sockets.pop().close()
        await shell.wait_slots(2)
        sockets.append(await shell.connect())
    finally:
        for ws in sockets:
            await ws.close()


async def test_session_origin_and_revocation_all_tabs(shell):
    for token, origin, status in [
        ("invalid", None, 401),
        (shell.token, "https://evil.invalid", 403),
    ]:
        with pytest.raises(WSServerHandshakeError) as rejected:
            await shell.connect(token=token, origin=origin)
        assert rejected.value.status == status
    sockets = [await shell.connect() for _ in range(3)]
    shell.store.logout(shell.token)
    for ws in sockets:
        async with asyncio.timeout(2):
            while (await ws.receive()).type == WSMsgType.BINARY:
                pass
        assert ws.close_code == 1008


async def test_key_path_has_no_sqlite_and_activity_is_batched_off_loop(
    shell, monkeypatch
):
    ws = await shell.connect()
    await input_text(ws, "stty -echo -icanon; printf '\\nREADY\\n'\r")
    await output_until(ws, b"READY\r\n")
    calls = []
    loop_thread = threading.get_ident()
    for name in ("session", "run", "update"):
        original = getattr(shell.store, name)

        def record(*args, _fn=original, _name=name, **kwargs):
            calls.append((_name, threading.get_ident(), kwargs.get("touch", False)))
            return _fn(*args, **kwargs)

        monkeypatch.setattr(shell.store, name, record)
    for _ in range(100):
        await input_text(ws, "a")
    await asyncio.sleep(0.2)
    assert calls and all(thread != loop_thread for _, thread, _ in calls)
    assert sum(name == "session" and touch for name, _, touch in calls) <= 2
    assert sum(name == "run" for name, _, _ in calls) < 10
    await ws.close()


async def test_slow_reader_preserves_all_bytes_and_escape_sequences(shell):
    ws = await shell.connect()
    await input_text(ws, "stty -echo; printf '\\nREADY\\n'\r")
    await output_until(ws, b"READY\r\n")
    # More than both bounded queues/windows. Pause the receiver before draining.
    await input_text(
        ws,
        'python3 -c \'import os; os.write(1,b"\\x1b[31mX\\x1b[0m"*200000); print("DONE")\'\r',
    )
    await asyncio.sleep(0.15)
    data = await output_until(ws, b"DONE\r\n")
    assert data.count(b"\x1b[31mX\x1b[0m") == 200000
    await ws.close()


async def test_resize_eof_and_malformed_message_release_slot(shell):
    ws = await shell.connect()
    await ws.send_json({"type": "resize", "rows": 37, "cols": 101})
    await input_text(ws, "stty -echo; stty size; exit\r")
    assert b"37 101" in await output_until(ws, b"37 101")
    await ws.close()
    ws = await shell.connect()
    await ws.send_str("not-json")
    async with asyncio.timeout(2):
        while (await ws.receive()).type == WSMsgType.BINARY:
            pass
    assert ws.close_code == 1008
    await shell.wait_slots(0)
    sockets = [await shell.connect() for _ in range(3)]
    for ws in sockets:
        await ws.close()


async def test_pty_reader_pauses_before_overflow_and_resumes():
    read_fd, write_fd = os.pipe()
    os.set_blocking(read_fd, False)
    output = terminal.PtyOutput(read_fd, capacity=2)
    try:
        os.write(write_fd, b"first")
        await asyncio.sleep(0.01)
        os.write(write_fd, b"second")
        await asyncio.sleep(0.01)
        assert output.queue.qsize() == 2 and not output.reading
        os.write(write_fd, b"third")
        assert await output.get() == b"first" and output.reading
        await asyncio.sleep(0.01)
        assert await output.get() == b"second"
        assert await output.get() == b"third"
        os.close(write_fd)
        write_fd = None
        assert await output.get() == b""
    finally:
        output.pause()
        os.close(read_fd)
        if write_fd is not None:
            os.close(write_fd)


async def test_partial_pty_writes_preserve_utf8(monkeypatch):
    payload = "Ω terminal ".encode() * 20
    written = bytearray()

    def short_write(fd, data):
        assert fd == 42
        chunk = bytes(data[:3])
        written.extend(chunk)
        return len(chunk)

    monkeypatch.setattr(terminal.os, "write", short_write)
    await terminal.write_pty(42, payload)
    assert bytes(written) == payload


async def test_blocked_pty_input_does_not_strand_closed_tab(shell, monkeypatch):
    blocked = asyncio.Event()

    async def unwritable(_fd, _data):
        blocked.set()
        await asyncio.Event().wait()

    monkeypatch.setattr(terminal, "write_pty", unwritable)
    monkeypatch.setattr(terminal, "INPUT_TIMEOUT", 0.05)
    ws = await shell.connect()
    await input_text(ws, "unread")
    await blocked.wait()
    await ws.close()
    await shell.wait_slots(0)
    sockets = [await shell.connect() for _ in range(3)]
    for ws in sockets:
        await ws.close()


async def test_cancelled_trace_worker_keeps_cross_tab_serialization(shell, monkeypatch):
    entered, release, second = threading.Event(), threading.Event(), threading.Event()
    original = shell.engine.command

    def command(run, line):
        if "FIRST_TRACE" in line:
            entered.set()
            assert release.wait(5)
        if "SECOND_TRACE" in line:
            second.set()
        original(run, line)

    monkeypatch.setattr(shell.engine, "command", command)
    one, two = await shell.connect(), await shell.connect()
    try:
        await input_text(one, "cat /dev/null; echo FIRST_TRACE\r")
        assert await asyncio.to_thread(entered.wait, 2)
        await one.close()
        await input_text(two, "cat /dev/null; echo SECOND_TRACE\r")
        await asyncio.sleep(0.15)
        assert not second.is_set(), "Cancelled worker released serialization too early"
        release.set()
        assert await asyncio.to_thread(second.wait, 2)
        await asyncio.sleep(0.1)
        run = shell.store.run(shell.run["id"], shell.run["user_id"])
        assert any("FIRST_TRACE" in line for line in run["commands"])
        assert any("SECOND_TRACE" in line for line in run["commands"])
    finally:
        release.set()
        await one.close()
        await two.close()


async def test_explicit_tab_close_acknowledges_reusable_slot(shell):
    sockets = [await shell.connect() for _ in range(3)]
    ws = sockets.pop(0)
    await ws.send_json({"type": "close"})
    async with asyncio.timeout(2):
        while (await ws.receive()).type == WSMsgType.BINARY:
            pass
    # No timing sleep: a close acknowledgement means cleanup and slot release.
    sockets.append(await shell.connect())
    for ws in sockets:
        await ws.close()


async def test_close_drains_completed_commands_even_with_slow_trace_writer(
    shell, monkeypatch
):
    import time

    original = shell.engine.command

    def slow(run, line):
        time.sleep(0.12)
        original(run, line)

    monkeypatch.setattr(shell.engine, "command", slow)
    ws = await shell.connect()
    await output_until(ws, b"fixture$ ")
    command = "cat /dev/null; printf 'DRAIN_%s\\n' COMPLETE\r"
    for _ in range(5):
        await input_text(ws, command)
        await output_until(ws, b"DRAIN_COMPLETE\r\n")
    await ws.send_json({"type": "close"})
    async with asyncio.timeout(10):
        async for message in ws:
            if message.type == WSMsgType.BINARY:
                await ws.send_json({"type": "ack", "bytes": len(message.data)})
    commands = shell.store.run(shell.run["id"], shell.run["user_id"])["commands"]
    assert len(commands) == 5, commands
    assert all(x.startswith("cat /dev/null;") for x in commands)
    await ws.close()


async def test_password_change_revokes_other_live_pty_but_keeps_current_session(shell):
    current = shell.store.session(shell.token)
    other = shell.store.login(
        "admin",
        (shell.store.path.parent / "admin-password").read_text().strip(),
        "other",
    )
    ws = await shell.connect(token=other)
    await output_until(ws, b"fixture$ ")
    shell.store.change_password(
        current,
        shell.token,
        (shell.store.path.parent / "admin-password").read_text().strip(),
        "new-fixture-password",
        "new-fixture-password",
    )
    async with asyncio.timeout(3):
        while (await ws.receive()).type == WSMsgType.BINARY:
            pass
    assert ws.close_code == 1008 and shell.store.session(shell.token)
