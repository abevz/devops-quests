"""Finish one recorded kind invocation even if the web backend exits.

The private lock prevents recovery from racing cluster creation. Recovery may
cancel an invocation that has not acquired the lock yet. No Docker access is
needed here: LabRuntime verifies the resulting container identities separately.
"""

import fcntl
import json
import os
import signal
import subprocess
import sys
from pathlib import Path


def save_record(path, value):
    temporary = path.with_suffix(".tmp")
    with temporary.open("w") as stream:
        json.dump(value, stream)
        stream.flush()
        os.fsync(stream.fileno())
    temporary.chmod(0o600)
    temporary.replace(path)


def create(path, token):
    with path.with_suffix(".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        record = json.loads(path.read_text())
        if record["status"] != "pending" or record["token"] != token:
            return
        record["status"] = "running"
        save_record(path, record)
        try:
            process = subprocess.Popen(
                record["command"],
                env=dict(os.environ, **record["environment"]),
                start_new_session=True,
            )
            try:
                record["returncode"] = process.wait(timeout=300)
            except subprocess.TimeoutExpired:
                # This process group was created only for this invocation.
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                record["returncode"] = -1
                record["error"] = "kind creation timed out"
        except OSError as error:
            record["returncode"] = -1
            record["error"] = str(error)
        finally:
            record["status"] = "finished"
            save_record(path, record)


if __name__ == "__main__":
    create(Path(sys.argv[1]), sys.argv[2])
