"""VM daily backup reads a running source and produces a restorable private copy."""

import importlib.util
import sqlite3
import stat
from pathlib import Path

import pytest

MODULE = Path(__file__).parents[1] / "deploy/backup_progress.py"
spec = importlib.util.spec_from_file_location("backup_progress", MODULE)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def test_online_backup_preserves_committed_wal_and_permissions(tmp_path):
    source = tmp_path / "progress.db"
    with sqlite3.connect(source) as connection:
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("CREATE TABLE progress(user_id INTEGER, level INTEGER)")
        connection.execute("INSERT INTO progress VALUES(4,27)")
        connection.commit()
        destination = tmp_path / "private" / "snapshot.db"
        module.backup(source, destination)
        assert connection.execute("SELECT * FROM progress").fetchall() == [(4, 27)]
        with sqlite3.connect(destination) as restored:
            assert restored.execute("SELECT * FROM progress").fetchall() == [(4, 27)]
            assert restored.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        assert stat.S_IMODE(destination.stat().st_mode) == 0o600
        assert stat.S_IMODE(destination.parent.stat().st_mode) == 0o700
        with pytest.raises(FileExistsError):
            module.backup(source, destination)


def test_missing_source_does_not_initialize_database(tmp_path):
    source = tmp_path / "missing.db"
    with pytest.raises(FileNotFoundError):
        module.backup(source, tmp_path / "backup.db")
    assert not source.exists()
