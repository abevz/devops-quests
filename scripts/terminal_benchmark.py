"""Real Docker/PTy/WebSocket benchmark, isolated from player profiles and bays.

Run with a disposable --container using the tested workstation image. The
container is supplied and removed by the caller. Only /tmp fixture files there
and a TemporaryDirectory profile are used. No reference solution is executed.
"""

import argparse
import asyncio
import json
import statistics
import tempfile
import time
from pathlib import Path
from urllib.parse import urlsplit

from aiohttp import ClientSession, WSMsgType, web
from aiohttp.test_utils import TestClient, TestServer

from devops_quests.catalog import Catalog
from devops_quests.engine import Engine
from devops_quests.server import COOKIE, make_app
from devops_quests.store import Store


class ProductionTestServer(TestServer):
    async def _make_runner(self, **kwargs):
        # TestServer forces True; the actual web.run_app entrypoint uses False.
        kwargs["handler_cancellation"] = False
        return await super()._make_runner(**kwargs)


def fixture(container, directory):
    class Runtime:
        def names(self, _run):
            return {"workstation": container}

        def owned(self, name):
            return name == container

        def teardown(self, _run):
            pass

    class FixtureEngine(Engine):
        async def background(self):
            await asyncio.Event().wait()

    store = Store(Path(directory) / "progress.db")
    password = store.bootstrap().read_text().strip()
    token = store.login("admin", password, "fixture")
    store.create_run(store.session(token)["user_id"], 1, "normal")
    return make_app(store, Catalog(), FixtureEngine(store, Catalog(), Runtime())), token


async def benchmark(container, samples, output, url=None, token_file=None):
    with tempfile.TemporaryDirectory(prefix="dq-terminal-bench-") as directory:
        if url:
            client = ClientSession(base_url=url)
            token = Path(token_file).read_text().strip()
            parsed = urlsplit(url)
            origin = parsed.scheme + "://" + parsed.netloc
            endpoint = "api/terminal"
        else:
            app, token = fixture(container, directory)
            client = TestClient(ProductionTestServer(app))
            await client.start_server()
            origin = str(client.make_url("/")).rstrip("/")
            endpoint = "/api/terminal"
        try:
            ws = await client.ws_connect(
                endpoint,
                headers={"Origin": origin, "Cookie": f"{COOKIE}={token}"},
            )

            async def send(text):
                await ws.send_json({"type": "input", "data": text})

            pending = bytearray()

            async def until(marker, timeout=30):
                async with asyncio.timeout(timeout):
                    while marker not in pending:
                        message = await ws.receive()
                        if message.type != WSMsgType.BINARY:
                            raise RuntimeError(f"Unexpected WS type {message.type}")
                        pending.extend(message.data)
                        # New protocol bounds the xterm pending-output window.
                        await ws.send_json({"type": "ack", "bytes": len(message.data)})
                end = pending.index(marker) + len(marker)
                data = bytes(pending[:end])
                del pending[:end]
                return data

            await until(b"$ ")
            await send(
                "stty -echo -icanon min 1 time 0; python3 -u -c 'import os; "
                'print("RAW_READY",flush=True); '
                "[os.write(1,os.read(0,1)) for _ in range("
                + str(samples + 10)
                + ")]'\r"
            )
            await until(b"RAW_READY\r\n")
            latency = []
            for index in range(samples + 10):
                char = bytes([65 + index % 26])
                start = time.perf_counter()
                await send(char.decode())
                await until(char)
                if index >= 10:
                    latency.append((time.perf_counter() - start) * 1000)
            await until(b"$ ")
            results = {}
            for label, command, expected in [
                (
                    "cat",
                    "head -c 4194304 /dev/zero | tr '\\0' x > /tmp/dq-terminal-bench.bin; cat /tmp/dq-terminal-bench.bin",
                    4194304,
                ),
                ("yes_head", "yes 1234567 | head -n 131072", 131072 * 9),
            ]:
                await send(
                    "printf '\\nBEGIN_PAYLOAD\\n'; "
                    + command
                    + "; printf '\\nEND_PAYLOAD\\n'\r"
                )
                start = time.perf_counter()
                data = await until(b"END_PAYLOAD\r\n", timeout=90)
                elapsed = time.perf_counter() - start
                payload = data.split(b"BEGIN_PAYLOAD\r\n", 1)[1].rsplit(
                    b"\r\nEND_PAYLOAD\r\n", 1
                )[0]
                results[label] = {
                    "bytes": len(payload),
                    "expected_bytes": expected,
                    "complete": len(payload) == expected,
                    "seconds": elapsed,
                    "MiB_s": len(payload) / 1048576 / elapsed,
                }
            ordered = sorted(latency)
            result = {
                "samples": samples,
                "echo_p50_ms": statistics.median(latency),
                "echo_p95_ms": ordered[int(len(ordered) * 0.95)],
                "throughput": results,
            }
            Path(output).write_text(json.dumps(result, indent=2) + "\n")
            print(json.dumps(result), flush=True)
            await ws.close()
        finally:
            await client.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--container", required=True)
    parser.add_argument("--samples", type=int, default=100)
    parser.add_argument("--output")
    parser.add_argument("--url")
    parser.add_argument("--token-file")
    parser.add_argument("--serve", action="store_true")
    parser.add_argument("--port", type=int, default=8768)
    args = parser.parse_args()
    if args.serve:
        with tempfile.TemporaryDirectory(prefix="dq-terminal-server-") as directory:
            app, token = fixture(args.container, directory)
            target = Path(args.token_file)
            target.touch(mode=0o600, exist_ok=False)
            target.write_text(token)
            try:
                web.run_app(app, host="127.0.0.1", port=args.port)
            finally:
                target.unlink(missing_ok=True)
    else:
        if not args.output or (args.url and not args.token_file):
            parser.error(
                "--output and, for external fixtures, --token-file are required"
            )
        asyncio.run(
            benchmark(
                args.container, args.samples, args.output, args.url, args.token_file
            )
        )
