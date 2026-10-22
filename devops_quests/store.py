"""Private profile/progress storage; normal play and exams are separate."""

import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path

from .scoring import POLICY, breakdown

IDLE = 2 * 60 * 60
ABSOLUTE = 24 * 60 * 60
ITERATIONS = 600_000


def password_hash(password):
    if not isinstance(password, str) or not 12 <= len(password) <= 128:
        raise ValueError("error.password")
    salt = secrets.token_hex(16)
    result = hashlib.pbkdf2_hmac(
        "sha256", password.encode(), bytes.fromhex(salt), ITERATIONS
    ).hex()
    return f"pbkdf2-sha256${ITERATIONS}${salt}${result}"


def password_matches(password, encoded):
    try:
        _, rounds, salt, expected = encoded.split("$")
        actual = hashlib.pbkdf2_hmac(
            "sha256", password.encode(), bytes.fromhex(salt), int(rounds)
        ).hex()
        return hmac.compare_digest(actual, expected)
    except (ValueError, TypeError):
        return False


class Store:
    def __init__(self, path, clock=time.time):
        self.path = Path(path)
        self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.clock = clock
        with self.connect() as db:
            db.executescript("""
            CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY, name TEXT UNIQUE NOT NULL,
              password TEXT NOT NULL, admin INTEGER NOT NULL DEFAULT 0, created REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS preferences(user_id INTEGER PRIMARY KEY REFERENCES users(id),
              primary_language TEXT, translation_language TEXT);
            CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY, user_id INTEGER REFERENCES users(id),
              csrf TEXT NOT NULL, created REAL NOT NULL, seen REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS login_attempts(bucket TEXT PRIMARY KEY, count INTEGER, until REAL);
            CREATE TABLE IF NOT EXISTS runs(id TEXT PRIMARY KEY, user_id INTEGER REFERENCES users(id),
              level INTEGER NOT NULL, mode TEXT NOT NULL, status TEXT NOT NULL, started REAL NOT NULL,
              activity REAL NOT NULL, deadline REAL, stage INTEGER DEFAULT 0, hints INTEGER DEFAULT 0,
              resets INTEGER DEFAULT 0, goals TEXT DEFAULT '[]', events TEXT DEFAULT '[]',
              commands TEXT DEFAULT '[]', score INTEGER DEFAULT 0, ended REAL);
            CREATE UNIQUE INDEX IF NOT EXISTS one_active_bay ON runs(user_id) WHERE status='active';
            CREATE TABLE IF NOT EXISTS progress(user_id INTEGER, level INTEGER, score INTEGER,
              seconds REAL, hints INTEGER, finished REAL, achievements TEXT,
              PRIMARY KEY(user_id,level));
            CREATE TABLE IF NOT EXISTS labs(id TEXT PRIMARY KEY,
              user_id INTEGER NOT NULL REFERENCES users(id), profile TEXT NOT NULL,
              version TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'stopped',
              slot INTEGER NOT NULL DEFAULT 0, created REAL NOT NULL, updated REAL NOT NULL,
              error TEXT NOT NULL DEFAULT '');
            CREATE UNIQUE INDEX IF NOT EXISTS one_saved_profile ON labs(user_id,profile)
              WHERE status != 'deleted';
            """)
            # Additive migration: preserve the original best-result rows. Seed
            # their campaign qualification once, never from later free results.
            db.execute("BEGIN IMMEDIATE")
            first_routes = not db.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name='completion_routes'"
            ).fetchone()
            if "route" not in {row[1] for row in db.execute("PRAGMA table_info(runs)")}:
                db.execute("ALTER TABLE runs ADD COLUMN route TEXT NOT NULL DEFAULT ''")
            if "disabled" not in {
                row[1] for row in db.execute("PRAGMA table_info(users)")
            }:
                db.execute(
                    "ALTER TABLE users ADD COLUMN disabled INTEGER NOT NULL DEFAULT 0"
                )
            db.execute("""CREATE TABLE IF NOT EXISTS completion_routes(
                user_id INTEGER REFERENCES users(id), level INTEGER, route TEXT,
                PRIMARY KEY(user_id,level,route))""")
            if first_routes:
                db.execute("""INSERT INTO completion_routes
                    SELECT user_id,level,'campaign' FROM progress""")
            db.execute("""
                CREATE TABLE IF NOT EXISTS briefing_hints(
                    user_id INTEGER REFERENCES users(id), level INTEGER,
                    count INTEGER NOT NULL, PRIMARY KEY(user_id,level))
            """)
            db.execute("""
                CREATE TABLE IF NOT EXISTS run_score_details(
                    run_id TEXT PRIMARY KEY REFERENCES runs(id), previous_best TEXT)
            """)
            # A code-only rollback may have recorded a normal pass using the
            # old release. Recover that explicit evidence on the next start.
            db.execute("""INSERT OR IGNORE INTO completion_routes
                SELECT user_id,level,'campaign' FROM runs
                WHERE mode='normal' AND status='passed'""")
        self.path.chmod(0o600)

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=20)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        try:
            yield db
            db.commit()
        finally:
            db.close()

    def bootstrap(self):
        with self.connect() as db:
            if db.execute("SELECT 1 FROM users LIMIT 1").fetchone():
                return None
            password = secrets.token_urlsafe(18)
            db.execute(
                "INSERT INTO users(name,password,admin,created) VALUES(?,?,1,?)",
                ("admin", password_hash(password), self.clock()),
            )
            target = self.path.parent / "admin-password"
            fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w") as file:
                file.write(password + "\n")
            return target

    def initialize_admin(self, name, password):
        """Create an explicitly requested first account; never reset existing users."""
        if not isinstance(name, str) or not re.fullmatch(
            r"[a-z][a-z0-9_-]{2,31}", name
        ):
            raise ValueError("error.username")
        encoded = password_hash(password)
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            if db.execute("SELECT 1 FROM users LIMIT 1").fetchone():
                return False
            db.execute(
                "INSERT INTO users(name,password,admin,created) VALUES(?,?,1,?)",
                (name, encoded, self.clock()),
            )
        return True

    def preferences(self, user_id):
        with self.connect() as db:
            row = db.execute(
                "SELECT primary_language,translation_language FROM preferences WHERE user_id=?",
                (user_id,),
            ).fetchone()
        return (
            {"primary": row[0], "translation": row[1]}
            if row
            else {"primary": None, "translation": None}
        )

    def set_preferences(self, user_id, primary, translation):
        with self.connect() as db:
            db.execute(
                "INSERT INTO preferences(user_id,primary_language,translation_language) VALUES(?,?,?) ON CONFLICT(user_id) DO UPDATE SET primary_language=excluded.primary_language,translation_language=excluded.translation_language",
                (user_id, primary, translation),
            )
        return self.preferences(user_id)

    def add_user(self, name, password, actor):
        if not actor.get("admin"):
            raise PermissionError("error.admin")
        if not isinstance(name, str) or not re.fullmatch(
            r"[a-z][a-z0-9_-]{2,31}", name
        ):
            raise ValueError("error.username")
        encoded = password_hash(password)
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            self._actor(db, actor, admin=True)
            db.execute(
                "INSERT INTO users(name,password,created) VALUES(?,?,?)",
                (name, encoded, self.clock()),
            )

    @staticmethod
    def _actor(db, actor, admin=False):
        user = db.execute(
            "SELECT * FROM users WHERE id=?", (actor["user_id"],)
        ).fetchone()
        if not user or user["disabled"] or (admin and not user["admin"]):
            raise PermissionError("error.admin" if admin else "error.unauthorized")
        return user

    def users(self, actor):
        with self.connect() as db:
            self._actor(db, actor, admin=True)
            return [
                {
                    "id": row["id"],
                    "name": row["name"],
                    "admin": bool(row["admin"]),
                    "enabled": not row["disabled"],
                }
                for row in db.execute(
                    "SELECT id,name,admin,disabled FROM users ORDER BY id"
                )
            ]

    def change_password(self, actor, token, current, password, confirmation):
        if password != confirmation:
            raise ValueError("error.password_confirmation")
        if not isinstance(password, str) or not 12 <= len(password) <= 128:
            raise ValueError("error.password")
        token_hash = hashlib.sha256((token or "").encode()).hexdigest()
        failure = False
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            user = self._actor(db, actor)
            if not db.execute(
                "SELECT 1 FROM sessions WHERE token=? AND user_id=?",
                (token_hash, user["id"]),
            ).fetchone():
                raise PermissionError("error.unauthorized")
            bucket, now = "password:" + str(user["id"]), self.clock()
            attempt = db.execute(
                "SELECT count,until FROM login_attempts WHERE bucket=?", (bucket,)
            ).fetchone()
            if attempt and attempt[1] > now and attempt[0] >= 8:
                raise PermissionError("error.attempts")
            if not isinstance(current, str) or not password_matches(
                current[:129], user["password"]
            ):
                db.execute(
                    """INSERT INTO login_attempts VALUES(?,1,?) ON CONFLICT(bucket)
                    DO UPDATE SET count=CASE WHEN until<? THEN 1 ELSE count+1 END,until=?""",
                    (bucket, now + 900, now, now + 900),
                )
                failure = True
            else:
                db.execute(
                    "UPDATE users SET password=? WHERE id=?",
                    (password_hash(password), user["id"]),
                )
                db.execute(
                    "DELETE FROM sessions WHERE user_id=? AND token<>?",
                    (user["id"], token_hash),
                )
                db.execute("DELETE FROM login_attempts WHERE bucket=?", (bucket,))
        # Commit failed-attempt counters before reporting the validation error.
        if failure:
            raise ValueError("error.current_password")

    def reset_password(self, actor, user_id, password):
        # Reject non-admin requests before spending password-derivation CPU.
        with self.connect() as db:
            self._actor(db, actor, admin=True)
        encoded = password_hash(password)
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            self._actor(db, actor, admin=True)
            if not db.execute("SELECT 1 FROM users WHERE id=?", (user_id,)).fetchone():
                raise ValueError("error.user_missing")
            db.execute("UPDATE users SET password=? WHERE id=?", (encoded, user_id))
            db.execute("DELETE FROM sessions WHERE user_id=?", (user_id,))
            db.execute(
                "DELETE FROM login_attempts WHERE bucket=?",
                ("password:" + str(user_id),),
            )

    def set_enabled(self, actor, user_id, enabled):
        if enabled is not True and enabled is not False:
            raise ValueError("error.request")
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            self._actor(db, actor, admin=True)
            target = db.execute(
                "SELECT admin,disabled FROM users WHERE id=?", (user_id,)
            ).fetchone()
            if target is None:
                raise ValueError("error.user_missing")
            if (
                not enabled
                and target["admin"]
                and not target["disabled"]
                and (
                    db.execute(
                        "SELECT count(*) FROM users WHERE admin=1 AND disabled=0"
                    ).fetchone()[0]
                    <= 1
                )
            ):
                raise ValueError("error.last_admin")
            db.execute("UPDATE users SET disabled=? WHERE id=?", (not enabled, user_id))
            if not enabled:
                db.execute("DELETE FROM sessions WHERE user_id=?", (user_id,))

    def login(self, name, password, address):
        now = self.clock()
        buckets = ("ip:" + address, "user:" + name[:64].lower())
        with self.connect() as db:
            for bucket in buckets:
                attempt = db.execute(
                    "SELECT * FROM login_attempts WHERE bucket=?", (bucket,)
                ).fetchone()
                if attempt and attempt["until"] > now and attempt["count"] >= 8:
                    raise PermissionError("error.attempts")
            user = db.execute("SELECT * FROM users WHERE name=?", (name,)).fetchone()
            # A dummy derivation keeps an unknown name from being a fast path.
            dummy = f"pbkdf2-sha256${ITERATIONS}$" + "00" * 16 + "$" + "00" * 32
            valid = password_matches(
                password[:129], user["password"] if user else dummy
            )
            if not user or not valid or user["disabled"]:
                for bucket in buckets:
                    db.execute(
                        """INSERT INTO login_attempts VALUES(?,1,?) ON CONFLICT(bucket)
                      DO UPDATE SET count=CASE WHEN until<? THEN 1 ELSE count+1 END, until=?""",
                        (bucket, now + 900, now, now + 900),
                    )
                return None
            db.execute("DELETE FROM login_attempts WHERE bucket=?", (buckets[1],))
            token, csrf = secrets.token_urlsafe(32), secrets.token_urlsafe(24)
            db.execute(
                "INSERT INTO sessions VALUES(?,?,?,?,?)",
                (
                    hashlib.sha256(token.encode()).hexdigest(),
                    user["id"],
                    csrf,
                    now,
                    now,
                ),
            )
            return token

    def session(self, token, touch=False):
        digest = hashlib.sha256((token or "").encode()).hexdigest()
        now = self.clock()
        with self.connect() as db:
            row = db.execute(
                """SELECT s.*,u.name,u.admin FROM sessions s JOIN users u ON u.id=s.user_id
              WHERE token=? AND u.disabled=0""",
                (digest,),
            ).fetchone()
            if not row:
                return None
            if now - row["seen"] >= IDLE or now - row["created"] >= ABSOLUTE:
                db.execute("DELETE FROM sessions WHERE token=?", (digest,))
                return None
            if touch:
                db.execute("UPDATE sessions SET seen=? WHERE token=?", (now, digest))
            return dict(row)

    def logout(self, token):
        with self.connect() as db:
            db.execute(
                "DELETE FROM sessions WHERE token=?",
                (hashlib.sha256((token or "").encode()).hexdigest(),),
            )

    def progress(self, user):
        with self.connect() as db:
            return [
                dict(row)
                for row in db.execute(
                    "SELECT * FROM progress WHERE user_id=? ORDER BY level", (user,)
                )
            ]

    def completions(self, user, route):
        with self.connect() as db:
            return {
                row[0]
                for row in db.execute(
                    "SELECT level FROM completion_routes WHERE user_id=? AND route=?",
                    (user, route),
                )
            }

    def attempted(self, user):
        with self.connect() as db:
            return [
                row[0]
                for row in db.execute(
                    "SELECT DISTINCT level FROM runs WHERE user_id=?", (user,)
                )
            ]

    def completed_any(self, user):
        with self.connect() as db:
            return {
                row[0]
                for row in db.execute(
                    "SELECT level FROM progress WHERE user_id=? UNION SELECT level FROM runs WHERE user_id=? AND status='passed'",
                    (user, user),
                )
            }

    def briefing_hint_count(self, user, level):
        with self.connect() as db:
            row = db.execute(
                "SELECT count FROM briefing_hints WHERE user_id=? AND level=?",
                (user, level),
            ).fetchone()
            return row[0] if row else 0

    def reveal_briefing_hint(self, user, level, total, confirmed=False):
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            self._actor(db, {"user_id": user})
            if db.execute(
                "SELECT 1 FROM progress WHERE user_id=? AND level=? UNION SELECT 1 FROM runs WHERE user_id=? AND level=? AND status='passed'",
                (user, level, user, level),
            ).fetchone():
                return total
            if db.execute(
                "SELECT 1 FROM runs WHERE user_id=? AND status='active'", (user,)
            ).fetchone():
                raise ValueError("error.active")
            row = db.execute(
                "SELECT count FROM briefing_hints WHERE user_id=? AND level=?",
                (user, level),
            ).fetchone()
            count = row[0] if row else 0
            if not count and confirmed is not True:
                raise PermissionError("error.hint_confirm")
            count = min(total, POLICY["hint_limit"], count + 1)
            db.execute(
                "INSERT INTO briefing_hints VALUES(?,?,?) ON CONFLICT(user_id,level) DO UPDATE SET count=excluded.count",
                (user, level, count),
            )
            return count

    def exams(self, user):
        with self.connect() as db:
            return [
                self.decode(row)
                for row in db.execute(
                    "SELECT * FROM runs WHERE user_id=? AND mode='exam' ORDER BY started DESC LIMIT 50",
                    (user,),
                )
            ]

    def history(self, user):
        with self.connect() as db:
            return [
                dict(row)
                for row in db.execute(
                    "SELECT id,level,mode,status,score,hints,resets,started FROM runs WHERE user_id=? AND mode!='exam' ORDER BY started DESC,rowid DESC LIMIT 50",
                    (user,),
                )
            ]

    @staticmethod
    def decode(row):
        if not row:
            return None
        data = dict(row)
        for key in ("goals", "events", "commands"):
            if key in data:
                data[key] = json.loads(data[key])
        return data

    def run(self, identifier=None, user=None):
        with self.connect() as db:
            if identifier:
                return self.decode(
                    db.execute(
                        "SELECT * FROM runs WHERE id=? AND user_id=?",
                        (identifier, user),
                    ).fetchone()
                )
            return self.decode(
                db.execute(
                    "SELECT * FROM runs WHERE user_id=? ORDER BY started DESC LIMIT 1",
                    (user,),
                ).fetchone()
            )

    def active(self):
        with self.connect() as db:
            return [
                self.decode(row)
                for row in db.execute("SELECT * FROM runs WHERE status='active'")
            ]

    def create_run(self, user, level, mode, minutes=15, route=""):
        now = self.clock()
        identifier = secrets.token_hex(12)
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            self._actor(db, {"user_id": user})
            if db.execute("SELECT 1 FROM labs WHERE slot=1").fetchone():
                raise ValueError("error.lab_busy")
            pending = db.execute(
                "SELECT count FROM briefing_hints WHERE user_id=? AND level=?",
                (user, level),
            ).fetchone()
            db.execute(
                "INSERT INTO runs(id,user_id,level,mode,status,started,activity,deadline,route,hints) VALUES(?,?,?,?,'active',?,?,?,?,?)",
                (
                    identifier,
                    user,
                    level,
                    mode,
                    now,
                    now,
                    now + minutes * 60 if mode == "exam" else None,
                    route,
                    pending[0] if pending and mode != "exam" else 0,
                ),
            )
            db.execute(
                "DELETE FROM briefing_hints WHERE user_id=? AND level=?", (user, level)
            )
        return self.run(identifier, user)

    def labs(self, user=None, occupied=False):
        with self.connect() as db:
            where, args = ["status != 'deleted'"], []
            if user is not None:
                where.append("user_id=?")
                args.append(user)
            if occupied:
                where.append("slot=1")
            return [
                dict(row)
                for row in db.execute(
                    "SELECT * FROM labs WHERE "
                    + " AND ".join(where)
                    + " ORDER BY created",
                    args,
                )
            ]

    def lab(self, identifier, user):
        with self.connect() as db:
            row = db.execute(
                "SELECT * FROM labs WHERE id=? AND user_id=? AND status!='deleted'",
                (identifier, user),
            ).fetchone()
            return dict(row) if row else None

    def save_lab(self, user, profile, version):
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            self._actor(db, {"user_id": user})
            row = db.execute(
                "SELECT * FROM labs WHERE user_id=? AND profile=? AND status!='deleted'",
                (user, profile),
            ).fetchone()
            if row:
                return dict(row)
            identifier, now = secrets.token_hex(12), self.clock()
            db.execute(
                "INSERT INTO labs(id,user_id,profile,version,created,updated) VALUES(?,?,?,?,?,?)",
                (identifier, user, profile, version, now, now),
            )
        return self.lab(identifier, user)

    def reserve_lab(self, lab):
        """Durable global reservation; a failed stop keeps this reservation."""
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            self._actor(db, {"user_id": lab["user_id"]})
            if (
                db.execute("SELECT 1 FROM runs WHERE status='active'").fetchone()
                or db.execute(
                    "SELECT 1 FROM labs WHERE slot=1 AND id!=?", (lab["id"],)
                ).fetchone()
            ):
                raise ValueError("error.lab_busy")
            db.execute(
                "UPDATE labs SET slot=1,status='preparing',error='',updated=? WHERE id=? AND status!='deleted'",
                (self.clock(), lab["id"]),
            )

    def update_lab(self, lab, **fields):
        if not fields or not fields.keys() <= {"status", "slot", "error"}:
            raise ValueError("Unknown lab fields")
        fields["updated"] = self.clock()
        with self.connect() as db:
            db.execute(
                "UPDATE labs SET " + ",".join(k + "=?" for k in fields) + " WHERE id=?",
                (*fields.values(), lab["id"]),
            )

    def ready(self, run):
        """Start the playable timer only after sandbox preparation succeeds."""
        now = self.clock()
        duration = run["deadline"] - run["started"] if run["deadline"] else None
        with self.connect() as db:
            db.execute(
                "UPDATE runs SET started=?,activity=?,deadline=? WHERE id=? AND status='active'",
                (now, now, now + duration if duration else None, run["id"]),
            )

    def update(self, run, **fields):
        allowed = {
            "status",
            "activity",
            "stage",
            "hints",
            "resets",
            "goals",
            "events",
            "commands",
            "score",
            "ended",
        }
        if not fields.keys() <= allowed:
            raise ValueError("Unknown run fields")
        encoded = {
            k: json.dumps(v) if k in {"goals", "events", "commands"} else v
            for k, v in fields.items()
        }
        with self.connect() as db:
            db.execute(
                "UPDATE runs SET "
                + ",".join(k + "=?" for k in encoded)
                + " WHERE id=?",
                (*encoded.values(), run["id"]),
            )

    def finish(self, run):
        now = self.clock()
        if run["deadline"] and now > run["deadline"]:
            self.update(run, status="expired", ended=now)
            return self.run(run["id"], run["user_id"])
        seconds = max(0, now - run["started"])
        score = breakdown(seconds, run["hints"], run["resets"])["score"]
        achievements = []
        if not run["hints"]:
            achievements.append("No hints")
        if seconds < POLICY["fast_seconds"]:
            achievements.append("Under five minutes")
        if not run["resets"]:
            achievements.append("No reset")
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            previous = db.execute(
                "SELECT score,seconds,hints FROM progress WHERE user_id=? AND level=?",
                (run["user_id"], run["level"]),
            ).fetchone()
            changed = db.execute(
                "UPDATE runs SET status='passed',score=?,ended=? WHERE id=? AND status='active'",
                (score, now, run["id"]),
            )
            if not changed.rowcount:
                return self.decode(
                    db.execute("SELECT * FROM runs WHERE id=?", (run["id"],)).fetchone()
                )
            db.execute(
                "INSERT INTO run_score_details VALUES(?,?)",
                (run["id"], json.dumps(dict(previous)) if previous else None),
            )
            if run["mode"] != "exam":
                previous = db.execute(
                    "SELECT achievements FROM progress WHERE user_id=? AND level=?",
                    (run["user_id"], run["level"]),
                ).fetchone()
                if previous:
                    achievements = sorted(
                        set(achievements) | set(json.loads(previous["achievements"]))
                    )
                db.execute(
                    """INSERT INTO progress VALUES(?,?,?,?,?,?,?) ON CONFLICT(user_id,level)
                  DO UPDATE SET score=excluded.score, seconds=excluded.seconds,
                  hints=excluded.hints,finished=excluded.finished,achievements=excluded.achievements
                  WHERE excluded.score > progress.score""",
                    (
                        run["user_id"],
                        run["level"],
                        score,
                        seconds,
                        run["hints"],
                        now,
                        json.dumps(achievements),
                    ),
                )
                route = (
                    "campaign"
                    if run["mode"] == "normal"
                    else "track:" + run["route"]
                    if run["mode"] == "track"
                    else None
                )
                if route:
                    db.execute(
                        "INSERT OR IGNORE INTO completion_routes VALUES(?,?,?)",
                        (run["user_id"], run["level"], route),
                    )
        return self.run(run["id"], run["user_id"])

    def score_details(self, run):
        with self.connect() as db:
            row = db.execute(
                "SELECT previous_best FROM run_score_details WHERE run_id=?",
                (run["id"],),
            ).fetchone()
        previous = json.loads(row[0]) if row and row[0] else None
        return {
            **breakdown(run["ended"] - run["started"], run["hints"], run["resets"]),
            "previous": previous,
            "previous_known": bool(row),
            "improved": bool(row)
            and (not previous or run["score"] > previous["score"]),
        }

    def backup(self, destination):
        target = Path(destination)
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        with self.connect() as db, sqlite3.connect(target) as output:
            db.backup(output)
            if output.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                raise RuntimeError("Backup integrity check failed")
        target.chmod(0o600)
