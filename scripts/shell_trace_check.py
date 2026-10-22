"""Check Bash history, real kubectl completion and editor isolation in an owned bay."""

import argparse
import asyncio
import json
import subprocess
import tempfile
from pathlib import Path

from aiohttp import WSMsgType
from aiohttp.test_utils import TestClient

from scripts.terminal_benchmark import ProductionTestServer, fixture


async def check(container):
    with tempfile.TemporaryDirectory(prefix="dq-history-check-") as directory:
        app, token = fixture(container, directory)
        client = TestClient(ProductionTestServer(app))
        await client.start_server()
        ws = await client.ws_connect(
            "/api/terminal",
            headers={
                "Origin": str(client.make_url("/")).rstrip("/"),
                "Cookie": "devops_quests_session=" + token,
            },
        )
        pending = bytearray()

        async def send(text):
            await ws.send_json({"type": "input", "data": text})

        async def until(marker):
            async with asyncio.timeout(15):
                while marker not in pending:
                    message = await ws.receive()
                    assert message.type == WSMsgType.BINARY, message
                    pending.extend(message.data)
                    await ws.send_json({"type": "ack", "bytes": len(message.data)})
            end = pending.index(marker) + len(marker)
            result = bytes(pending[:end])
            del pending[:end]
            return result

        async def command(text, marker):
            await send(text + "\r")
            data = await until(marker)
            await until(b"$ ")
            return data

        try:
            await until(b"$ ")
            namespaces = await command(
                "k get ns; printf 'NS_%s\\n' READY", b"NS_READY\r\n"
            )
            assert b"kube-system" in namespaces and b"Forbidden" not in namespaces, (
                namespaces
            )
            await command(
                "__dq_capture_line() { printf '%s' \"$READLINE_LINE\" > /tmp/dq-completion-line; }; bind -x '\"\\C-x\\C-p\":__dq_capture_line'; printf 'BIND_%s\\n' READY",
                b"BIND_READY\r\n",
            )
            await send("k get po\t\t")
            await asyncio.sleep(0.8)
            # Capture READLINE_LINE: terminal echo can interleave a completion
            # character with bells/control bytes, so it is not an exact line.
            await send("\x18\x10")
            await send("\x05\x15printf 'COMPLETE_%s\\n' READY\r")
            completion = await until(b"COMPLETE_READY\r\n")
            await until(b"$ ")
            completed = await asyncio.to_thread(
                subprocess.check_output,
                [
                    "docker",
                    "--host",
                    "unix:///var/run/docker.sock",
                    "exec",
                    "--user",
                    "1000:1000",
                    container,
                    "cat",
                    "/tmp/dq-completion-line",
                ],
                text=True,
            )
            assert completed.startswith("k get pod"), (completed, completion)
            await send("vim -n /tmp/dq-history-vim-fixture\r")
            await asyncio.sleep(0.3)
            await send(
                "iEDITOR_PRIVATE_TEXT\x1bOB\x1bOA\x1b[6~\x1b[200~EDITOR_PASTE_TEXT\x1b[201~"
            )
            await send(
                "\x1b[<2;19;18M\x1b[2;2R\x1b[>0;276;0c\x1b]10;rgb:ffff/ffff/ffff\x07\x1b[?2004;1$y"
            )
            await send("\x1b\x1b:q!\r")
            await until(b"$ ")
            pasted = "k get pods >/dev/null; printf 'PASTE_%s\\n' READY"
            await command("\x1b[200~" + pasted + "\x1b[201~", b"PASTE_READY\r\n")
            await command(
                "cat /dev/null; export DEMO_SECRET=fixture-canary; printf 'MASK_%s\\n' READY",
                b"MASK_READY\r\n",
            )
            # Read only this synthetic profile, never the player's database.
            import sqlite3

            deadline = asyncio.get_running_loop().time() + 5
            commands = []
            while asyncio.get_running_loop().time() < deadline:
                path = Path(directory) / "progress.db"
                with sqlite3.connect(path.as_uri() + "?mode=ro", uri=True) as db:
                    commands = json.loads(
                        db.execute("select commands from runs").fetchone()[0]
                    )
                if any("DEMO_SECRET=[REDACTED]" in x for x in commands):
                    break
                await asyncio.sleep(0.05)
            assert any(x.startswith("k get ns;") for x in commands), commands
            assert "vim -n /tmp/dq-history-vim-fixture" in commands, commands
            assert pasted in commands, commands
            joined = "\n".join(commands)
            assert "DEMO_SECRET=[REDACTED]" in joined and "fixture-canary" not in joined
            for forbidden in [
                "EDITOR_PRIVATE_TEXT",
                "EDITOR_PASTE_TEXT",
                "\x1b",
                "[6~",
                "[<2;",
                "[2;2R",
                "[>0;",
                "rgb:",
                "[200~",
                "[201~",
            ]:
                assert forbidden not in joined, (forbidden, commands)
            return {
                "k_get_namespaces": True,
                "k_completion": True,
                "vim_input_excluded": True,
                "terminal_replies_excluded": True,
                "bracketed_paste_clean": True,
                "secrets_redacted": True,
                "commands": commands,
            }
        finally:
            await ws.send_json({"type": "close"})
            async with asyncio.timeout(15):
                async for message in ws:
                    if message.type == WSMsgType.BINARY:
                        await ws.send_json({"type": "ack", "bytes": len(message.data)})
            await ws.close()
            await client.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--container", required=True)
    print(
        json.dumps(
            asyncio.run(check(parser.parse_args().container)), ensure_ascii=False
        )
    )
