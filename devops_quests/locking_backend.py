"""Bay-local HTTP state backend and bounded native-console completion service.

Executed as UID0 with no capabilities, a read-only source mount and a private
executable tmpfs. Only the registered child's stdin can be closed remotely.
"""

import http.server
import json
import subprocess
import threading
import time
import urllib.parse
from pathlib import Path

PRIVATE = Path('/var/lib/dq-lock')


class Backend:
    def __init__(self):
        self.guard = threading.RLock()
        self.state = None
        self.lock = None
        self.owner = {'registered': False}
        self.events = []
        self.finish = threading.Event()
        self.owner_lock = None

    def supervise(self):
        while not (PRIVATE / 'start-owner').exists():
            time.sleep(.05)
        with (PRIVATE / 'console.stdout').open('w') as stdout, (PRIVATE / 'console.stderr').open('w') as stderr:
            child = subprocess.Popen(['tofu', 'console', '-no-color'], cwd=PRIVATE / 'maintenance', stdin=subprocess.PIPE, stdout=stdout, stderr=stderr)
            while child.poll() is None:
                with self.guard:
                    if self.lock:
                        self.owner_lock = dict(self.lock)
                        self.owner = {'registered': True, 'handle': self.lock['ID'], 'running': True, 'eof_requested': False, 'completed': False}
                        break
                time.sleep(.05)
            while child.poll() is None and not self.finish.wait(.05):
                pass
            with self.guard:
                requested = self.finish.is_set() and child.poll() is None
                self.owner['eof_requested'] = requested
            if requested:
                child.stdin.close()
            code = child.wait()
        with self.guard:
            error = (PRIVATE / 'console.stderr').read_text()
            released = any(e['method'] == 'UNLOCK' and e['status'] == 200 and e.get('info') == self.owner_lock for e in self.events)
            self.owner.update(running=False, exit=code, stderr=error, completed=requested and code == 0 and not error and released)


def handler(backend):
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def reply(self, status, value=None):
            data = value if isinstance(value, bytes) else json.dumps(value).encode() if value is not None else b''
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def body(self, limit=2 * 1024 * 1024):
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= limit:
                raise ValueError('body size')
            raw = self.rfile.read(size)
            value = json.loads(raw)
            if not isinstance(value, dict):
                raise ValueError('JSON object required')
            return raw, value

        def do_GET(self):
            with backend.guard:
                if self.path == '/owner':
                    self.reply(200, backend.owner)
                elif self.path == '/diagnostic':
                    self.reply(200, {'lock': backend.lock, 'events': backend.events})
                elif self.path == '/deployment':
                    self.reply(200, backend.state) if backend.state is not None else self.reply(404)
                else:
                    self.reply(404)

        def do_POST(self):
            path = urllib.parse.urlsplit(self.path)
            try:
                raw, value = self.body(16384 if path.path == '/owner/finish' else 2 * 1024 * 1024)
            except (ValueError, OSError):
                return self.reply(400)
            with backend.guard:
                if path.path == '/owner/finish':
                    if set(value) != {'handle'} or not isinstance(value['handle'], str):
                        return self.reply(400)
                    if not backend.owner.get('registered') or value['handle'] != backend.owner.get('handle'):
                        return self.reply(409)
                    backend.finish.set()
                    return self.reply(202, {'requested': True})
                if path.path != '/deployment':
                    return self.reply(404)
                supplied = urllib.parse.parse_qs(path.query).get('ID', [''])[0]
                if (backend.lock and supplied != backend.lock['ID']) or (supplied and not backend.lock):
                    backend.events.append({'method': 'POST', 'status': 423, 'supplied': supplied})
                    return self.reply(423, backend.lock)
                backend.state = raw
                backend.events.append({'method': 'POST', 'status': 200, 'serial': value.get('serial')})
                self.reply(200)

        def do_LOCK(self):
            self.change_lock(False)

        def do_UNLOCK(self):
            self.change_lock(True)

        def change_lock(self, unlock):
            if urllib.parse.urlsplit(self.path).path != '/deployment':
                return self.reply(404)
            try:
                _, info = self.body(16384)
                if not isinstance(info.get('ID'), str) or not info['ID']:
                    raise ValueError('lock ID required')
            except (ValueError, OSError):
                return self.reply(400)
            with backend.guard:
                status = (200 if backend.lock and info['ID'] == backend.lock['ID'] else 409) if unlock else (423 if backend.lock else 200)
                backend.events.append({'method': self.command, 'status': status, 'info': info})
                if status == 200:
                    backend.lock = None if unlock else info
                self.reply(status, backend.lock if status != 200 else None)

        def do_DELETE(self):
            # The exercise's backend has no state-deletion operation.
            self.reply(405)

    return Handler


def main():
    backend = Backend()
    threading.Thread(target=backend.supervise, daemon=True).start()
    http.server.ThreadingHTTPServer(('127.0.0.1', 18787), handler(backend)).serve_forever()


if __name__ == '__main__':
    main()
