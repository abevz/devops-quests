"""The real-Docker probe waits for observed resize rather than a WS send."""

import asyncio
from types import SimpleNamespace

import pytest
from aiohttp import WSMsgType

from scripts.local_security_check import verify_pty


class Socket:
    def __init__(self, replies):
        self.replies = iter(replies)
        self.sent = []

    async def send_json(self, data):
        self.sent.append(data)

    async def receive(self):
        try:
            data = next(self.replies)
        except StopIteration:
            await asyncio.Event().wait()
        return SimpleNamespace(type=WSMsgType.BINARY, data=data)


async def test_resize_checks_real_output_after_a_stale_initial_size(tmp_path):
    ws = Socket(
        [
            b"canary\r\n1000\r\nfixture$ ",
            b"stty size\r\n0 0\r\nfixture$ ",
            b"stty size\r\n36 120\r\nfixture$ ",
        ]
    )
    await verify_pty(ws, "canary", tmp_path)
    commands = [item["data"] for item in ws.sent if item["type"] == "input"]
    assert commands[1:] == ["stty size\r", "stty size\r"]
    assert all("36 120" not in command for command in commands)
    assert sum(item["type"] == "ack" for item in ws.sent) == 3


async def test_resize_is_bounded_and_retains_observed_failure(tmp_path):
    ws = Socket([b"canary\r\n1000\r\nfixture$ ", b"0 0\r\nfixture$ "])
    with pytest.raises(TimeoutError):
        await verify_pty(ws, "canary", tmp_path, timeout=0.01)
    assert "0 0" in (tmp_path / "pty-timeout.txt").read_text()
