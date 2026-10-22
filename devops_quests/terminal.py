"""Bounded, lossless PTY transport with timed authentication and activity writes."""

import asyncio
import contextlib
import fcntl
import json
import os
import pty
import secrets
import signal
import struct
import subprocess
import termios
import threading

from aiohttp import WSMsgType, web

from .runtime import DOCKER

SESSION_INTERVAL = 2.0
ACTIVITY_INTERVAL = 5.0
MAX_TERMINALS = 3
OUTPUT_WINDOW = 64 * 1024
INPUT_TIMEOUT = 2.0

# Docker exec client termination alone leaves its remote Bash alive. Select the
# exact nonce-tagged session inside the owned workstation's PID namespace.
END_SHELL = r"""
import os, signal, sys, time
from pathlib import Path
tag = b'DQ_TERMINAL_ID=' + sys.argv[1].encode()
sessions = set()
tagged = set()
readers = set()
for p in Path('/proc').iterdir():
    if not p.name.isdigit(): continue
    try:
        environment = (p/'environ').read_bytes().split(b'\0')
        if tag in environment:
            pid = int(p.name)
            if b'DQ_TRACE_READER=1' in environment:
                readers.add(pid)
                continue
            sid = os.getsid(pid)
            if pid > 1: tagged.add(pid)
            if sid > 1: sessions.add(sid)
    except (OSError, ValueError): pass
for sig in (signal.SIGHUP, signal.SIGKILL):
    for p in Path('/proc').iterdir():
        if not p.name.isdigit(): continue
        try:
            pid = int(p.name)
            if pid not in readers and (os.getsid(pid) in sessions or pid in tagged): os.kill(pid, sig)
        except (OSError, ValueError): pass
    if sig == signal.SIGHUP: time.sleep(.05)
for pid in readers:
    try: os.kill(pid, signal.SIGUSR1)
    except ProcessLookupError: pass
(Path("/tmp") / ("dq-trace-" + sys.argv[1])).unlink(missing_ok=True)
"""


HISTORY_READER = r"""
import os, signal, stat, sys, time
from pathlib import Path
stopping = False
def stop(_signal, _frame):
    global stopping
    stopping = True
signal.signal(signal.SIGUSR1, stop)
path = Path(os.environ.get('DQ_TRACE_DIRECTORY', '/tmp')) / ('dq-trace-' + sys.argv[1])
for _ in range(100):
    if stopping: sys.exit(0)
    try:
        info = path.lstat()
        if not stat.S_ISFIFO(info.st_mode) or info.st_uid != os.getuid():
            raise RuntimeError('Invalid command channel')
        break
    except FileNotFoundError:
        time.sleep(.05)
else:
    raise RuntimeError('Command channel did not appear')
fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
try:
    while True:
        try: chunk = os.read(fd, 8192)
        except BlockingIOError: chunk = b''
        if not chunk:
            if stopping: break
            time.sleep(.01)
            continue
        view = memoryview(chunk)
        while view:
            count = os.write(1, view)
            if not count: raise RuntimeError('Command channel closed')
            view = view[count:]
finally:
    os.close(fd)
"""


def end_shell(name, identity):
    subprocess.run(
        [
            *DOCKER,
            "exec",
            "--user",
            "1000:1000",
            name,
            "python3",
            "-c",
            END_SHELL,
            identity,
        ],
        capture_output=True,
        timeout=5,
        check=False,
    )


class PtyOutput:
    """Pause the kernel reader before the bounded queue fills; never drop bytes."""

    def __init__(self, fd, capacity=128):
        self.fd = fd
        self.loop = asyncio.get_running_loop()
        self.queue = asyncio.Queue(maxsize=capacity)
        self.eof = False
        self.reading = False
        self.resume()

    def resume(self):
        if not self.eof and not self.reading and not self.queue.full():
            self.loop.add_reader(self.fd, self.readable)
            self.reading = True

    def pause(self):
        if self.reading:
            self.loop.remove_reader(self.fd)
            self.reading = False

    def readable(self):
        if self.queue.full():
            self.pause()
            return
        try:
            data = os.read(self.fd, 8192)
        except BlockingIOError:
            return
        except OSError:
            data = b""
        if not data:
            self.eof = True
        self.queue.put_nowait(data)
        if self.eof or self.queue.full():
            self.pause()

    async def get(self):
        data = await self.queue.get()
        self.resume()
        return data


async def write_pty(fd, data):
    """Honor partial/nonblocking writes, including a pasted multiline command."""
    loop = asyncio.get_running_loop()
    view = memoryview(data)
    while view:
        try:
            count = os.write(fd, view)
            if not count:
                raise ConnectionError("PTY stopped accepting input")
            view = view[count:]
        except BlockingIOError:
            ready = loop.create_future()

            def writable(ready=ready):
                if not ready.done():
                    ready.set_result(None)

            loop.add_writer(fd, writable)
            try:
                await ready
            finally:
                loop.remove_writer(fd)


class TerminalHub:
    def __init__(self, store, engine):
        self.store, self.engine = store, engine
        self.connections = {}
        self.sockets = set()
        # All tabs serialize read-modify-write command traces and activity.
        self.store_lock = threading.Lock()

    async def shutdown(self, _app):
        await asyncio.gather(
            *(
                ws.close(code=1001, message=b"Server restarting")
                for ws in list(self.sockets)
            ),
            return_exceptions=True,
        )

    async def serve(self, request, run, token, *, store=None, engine=None):
        user = run["user_id"]
        slots = self.connections.setdefault(user, set())
        if len(slots) >= MAX_TERMINALS:
            raise web.HTTPTooManyRequests(text="At most three terminals per user.")
        slot = object()
        # Reserve before any await, including Docker ownership and spawn.
        slots.add(slot)

        def release():
            slots.discard(slot)
            if not slots and self.connections.get(user) is slots:
                self.connections.pop(user, None)

        try:
            return await self.bridge(
                request, run, token, release, store=store, engine=engine
            )
        finally:
            release()

    async def bridge(self, request, run, token, release, *, store=None, engine=None):
        store, engine = store or self.store, engine or self.engine
        name = engine.runtime.names(run)["workstation"]
        if not await asyncio.to_thread(engine.runtime.owned, name):
            raise ValueError("The workstation is unavailable.")
        ws = web.WebSocketResponse(heartbeat=20, max_msg_size=16 * 1024)
        await ws.prepare(request)
        self.sockets.add(ws)
        master, slave = pty.openpty()
        identity = secrets.token_hex(16)
        process = history_process = output = None
        tasks = []
        closing = False
        try:
            try:
                process = await asyncio.create_subprocess_exec(
                    *DOCKER,
                    "exec",
                    "-it",
                    "--user",
                    "1000:1000",
                    "--env",
                    "TERM=xterm-256color",
                    "--env",
                    "DQ_TERMINAL_ID=" + identity,
                    name,
                    "/bin/bash",
                    "-il",
                    stdin=slave,
                    stdout=slave,
                    stderr=slave,
                    start_new_session=True,
                )
            finally:
                os.close(slave)
            os.set_blocking(master, False)
            output = PtyOutput(master)
            commands = asyncio.Queue(maxsize=64)
            history_process = await asyncio.create_subprocess_exec(
                *DOCKER,
                "exec",
                "--user",
                "1000:1000",
                "--env",
                "DQ_TERMINAL_ID=" + identity,
                "--env",
                "DQ_TRACE_READER=1",
                name,
                "python3",
                "-u",
                "-c",
                HISTORY_READER,
                identity,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                start_new_session=True,
            )

            async def capture_commands():
                pending = bytearray()
                oversized = False
                while chunk := await history_process.stdout.read(8192):
                    for part in chunk.split(b"\0")[:-1]:
                        if not oversized and len(pending) + len(part) <= 65536:
                            pending.extend(part)
                            await commands.put(
                                pending.decode("utf-8", errors="replace")
                            )
                        pending.clear()
                        oversized = False
                    # Keep the trailing partial frame. NUL is the only record delimiter.
                    tail = chunk.rsplit(b"\0", 1)[-1]
                    if b"\0" not in chunk:
                        pending.extend(chunk)
                    else:
                        pending.extend(tail)
                    if len(pending) > 65536:
                        pending.clear()
                        oversized = True
                if not closing and not ws.closed:
                    raise ConnectionError("Command channel ended")

            credit = asyncio.Event()
            credit.set()
            in_flight = 0
            activity = 0
            touched = 0
            last_touch = asyncio.get_running_loop().time()

            async def pump():
                nonlocal in_flight
                while not ws.closed:
                    data = await output.get()
                    if not data:
                        # Let xterm consume the final bytes before closing.
                        while in_flight and not ws.closed:
                            credit.clear()
                            await credit.wait()
                        await ws.close()
                        return
                    while in_flight + len(data) > OUTPUT_WINDOW and not ws.closed:
                        credit.clear()
                        await credit.wait()
                    if ws.closed:
                        return
                    in_flight += len(data)
                    await ws.send_bytes(data)

            async def validity():
                nonlocal touched, last_touch
                while not ws.closed:
                    await asyncio.sleep(SESSION_INTERVAL)
                    now = asyncio.get_running_loop().time()
                    observed = activity
                    touch = (
                        observed != touched and now - last_touch >= ACTIVITY_INTERVAL
                    )

                    def validate(touch=touch):
                        with self.store_lock:
                            session = store.session(token, touch=touch)
                            current = store.run(run["id"], run["user_id"])
                            valid = (
                                session and current and current["status"] == "active"
                            )
                            if valid and touch:
                                store.update(current, activity=store.clock())
                            return valid

                    valid = await asyncio.to_thread(validate)
                    if not valid:
                        await ws.close(code=1008, message=b"Session or quest ended")
                        return
                    if touch:
                        touched, last_touch = observed, now

            async def trace():
                while True:
                    line = await commands.get()

                    def record(line=line):
                        with self.store_lock:
                            current = store.run(run["id"], run["user_id"])
                            if current:
                                engine.command(current, line)

                    try:
                        await asyncio.to_thread(record)
                    finally:
                        commands.task_done()

            async def supervise(coroutine):
                try:
                    await coroutine
                except (ConnectionError, OSError):
                    await ws.close()
                except Exception:
                    import logging

                    logging.getLogger(__name__).exception("Terminal worker failed")
                    await ws.close(code=1011, message=b"Terminal unavailable")

            tasks = [
                asyncio.create_task(supervise(fn()))
                for fn in (pump, validity, trace, capture_commands)
            ]
            async for message in ws:
                if message.type == WSMsgType.TEXT:
                    try:
                        data = json.loads(message.data)
                        if not isinstance(data, dict):
                            raise TypeError("Expected object")
                        kind = data.get("type")
                        if kind == "close":
                            break
                        if kind == "resize":
                            rows = max(5, min(200, int(data.get("rows", 24))))
                            cols = max(20, min(400, int(data.get("cols", 80))))
                            fcntl.ioctl(
                                master,
                                termios.TIOCSWINSZ,
                                struct.pack("HHHH", rows, cols, 0, 0),
                            )
                            with contextlib.suppress(ProcessLookupError):
                                os.killpg(process.pid, signal.SIGWINCH)
                        elif kind == "ack":
                            count = data.get("bytes")
                            if not isinstance(count, int) or not 0 < count <= in_flight:
                                raise ValueError("Invalid output acknowledgement")
                            in_flight -= count
                            credit.set()
                        elif kind == "input":
                            text = data.get("data", "")
                            if not isinstance(text, str) or len(text.encode()) > 8192:
                                raise ValueError("Invalid input")
                            activity += 1
                            # A foreground command can stop reading its PTY. Bound
                            # the wait so a disconnected client cannot strand a slot.
                            await asyncio.wait_for(
                                write_pty(master, text.encode()), INPUT_TIMEOUT
                            )

                        else:
                            raise ValueError("Unknown terminal message")
                    except (ValueError, TypeError, OverflowError):
                        await ws.close(code=1008, message=b"Invalid terminal message")
                        break
                    except TimeoutError:
                        await ws.close(
                            code=1013, message=b"Terminal input stalled; reconnect"
                        )
                        break
                elif message.type == WSMsgType.ERROR:
                    break
        finally:
            closing = True
            # Stop PTY delivery/auth polling first. Keep the separate command
            # reader and DB worker alive until the shell has emitted its final
            # record and the channel/queue have drained.
            for task in tasks[:2]:
                task.cancel()
            await asyncio.gather(*tasks[:2], return_exceptions=True)
            if output:
                output.pause()
            if process:
                with contextlib.suppress(OSError, subprocess.TimeoutExpired):
                    await asyncio.to_thread(end_shell, name, identity)
            os.close(master)
            if process:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(process.pid, signal.SIGHUP)
            if len(tasks) == 4:
                try:
                    async with asyncio.timeout(5):
                        await asyncio.shield(tasks[3])
                        await commands.join()
                except TimeoutError:
                    import logging

                    logging.getLogger(__name__).warning(
                        "Command channel drain timed out"
                    )
            for task in tasks[2:]:
                task.cancel()
            await asyncio.gather(*tasks[2:], return_exceptions=True)
            if history_process:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(history_process.pid, signal.SIGTERM)
                try:
                    await asyncio.wait_for(history_process.communicate(), 5)
                except TimeoutError:
                    with contextlib.suppress(ProcessLookupError):
                        os.killpg(history_process.pid, signal.SIGKILL)
                    await history_process.communicate()
            if process:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(process.pid, signal.SIGTERM)
                try:
                    await asyncio.wait_for(process.wait(), 5)
                except TimeoutError:
                    with contextlib.suppress(ProcessLookupError):
                        os.killpg(process.pid, signal.SIGKILL)
                    await process.wait()
            # Explicit tab close is acknowledged only after the remote shell is
            # gone and the slot is reusable, avoiding a close/new-tab race.
            release()
            await ws.close()
            self.sockets.discard(ws)
        return ws
