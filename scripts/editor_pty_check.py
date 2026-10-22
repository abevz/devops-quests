"""Exercise system Vim through docker exec's actual xterm PTY, on fixture files."""

import argparse
import contextlib
import json
import os
import pty
import select
import subprocess
import time


def check_unicode_shell(container):
    master, slave = pty.openpty()
    process = subprocess.Popen(
        [
            "docker",
            "--host",
            "unix:///var/run/docker.sock",
            "exec",
            "-it",
            "--user",
            "1000:1000",
            "--env",
            "TERM=xterm-256color",
            container,
            "bash",
            "-il",
        ],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        start_new_session=True,
    )
    os.close(slave)
    received = bytearray()

    def until(marker):
        deadline = time.monotonic() + 5
        while marker not in received and time.monotonic() < deadline:
            if select.select([master], [], [], 0.1)[0]:
                received.extend(os.read(master, 65536))
        if marker not in received:
            raise AssertionError(
                "Interactive Bash did not preserve the Unicode argument"
            )

    try:
        until(b"$ ")
        os.write(
            master,
            "python3 -c 'import sys; print(\"UNICODE_\"+str(ord(sys.argv[1])))' Ω\r".encode(),
        )
        until(b"UNICODE_937")
        os.write(master, b"exit\r")
        process.wait(timeout=5)
        print(json.dumps({"interactive_unicode_shell": "PASS"}))
    finally:
        os.close(master)
        if process.poll() is None:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, 15)
            process.wait(timeout=5)


def check(container):
    docker = ["docker", "--host", "unix:///var/run/docker.sock"]
    path = "/tmp/dq-editor-pty-fixture.txt"
    subprocess.run(
        [
            *docker,
            "exec",
            "--user",
            "1000:1000",
            container,
            "bash",
            "-c",
            f"printf 'abcd\\nsecond\\n' > {path}",
        ],
        check=True,
    )
    master, slave = pty.openpty()
    process = subprocess.Popen(
        [
            *docker,
            "exec",
            "-it",
            "--user",
            "1000:1000",
            "--env",
            "TERM=xterm-256color",
            container,
            "vi",
            "-n",
            path,
        ],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        start_new_session=True,
    )
    os.close(slave)
    transcript = bytearray()

    def drain(seconds):
        until = time.monotonic() + seconds
        while time.monotonic() < until:
            ready, _, _ = select.select(
                [master], [], [], min(0.05, max(0, until - time.monotonic()))
            )
            if ready:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    return
                if not data:
                    return
                transcript.extend(data)

    try:
        drain(0.5)
        # Insert key, erase its character, then return to normal mode.
        for key in [b"gg0", b"\x1b[2~", b"Q", b"\x7f", b"\x1b"]:
            os.write(master, key)
            drain(0.15)
        # Move back before the insertion point and erase an original character.
        # CSI arrows are also what the touch extra-key strip sends.
        for key in [
            b"A",
            b"XY",
            b"\x1b[D",
            b"\x1b[D",
            b"\x7f",
            b"\x1b[C",
            b"\x1b[3~",
            b"\x1b[H",
            "Ω".encode(),
            b"\x1b[F",
            b"Z",
            b"\x1b",
        ]:
            os.write(master, key)
            drain(0.15)
        os.write(master, b":wq\r")
        drain(0.3)
        process.wait(timeout=10)
        actual = subprocess.check_output(
            [*docker, "exec", "--user", "1000:1000", container, "cat", path]
        ).decode()
        expected = "ΩabcXZ\nsecond\n"
        result = {
            "exit_code": process.returncode,
            "expected": expected,
            "actual": actual,
            "pass": actual == expected,
            "pty_output_bytes": len(transcript),
        }
        print(json.dumps(result, ensure_ascii=False))
        if not result["pass"]:
            raise AssertionError("PTY edit result differs from expected fixture")
    finally:
        os.close(master)
        if process.poll() is None:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, 15)
            process.wait(timeout=5)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--container", required=True)
    container = parser.parse_args().container
    check_unicode_shell(container)
    check(container)
