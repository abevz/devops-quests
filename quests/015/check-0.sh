set -euo pipefail
cd ~/quest
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
set -euo pipefail
cd ~/quest
python3 -I - "$DQ_NAMESPACE" <<'DQ_ROUTES'
import re, shlex, subprocess, sys
from pathlib import Path
import yaml
try:
    routes = yaml.safe_load(Path('routes.yml').read_text())['routes']
    if not isinstance(routes, list) or not routes:
        raise ValueError('route list')
    if not all(isinstance(route, str) and route not in ('.', '..') and re.fullmatch(r'[^/\x00\r\n]+', route) for route in routes):
        raise ValueError('route name')
    if len(set(routes)) != len(routes):
        raise ValueError('duplicate route')
except (OSError, ValueError, TypeError, KeyError, yaml.YAMLError):
    print('routes.yml must contain a nonempty list of distinct route names: ✗ [DQ:routes]')
    sys.exit(1)
failed = False
for host in range(1, 4):
    lines = ['failed=0']
    for route in routes:
        path = shlex.quote('/srv/routes/' + route)
        marker = f'directory_{route}_{host}' if route in ('north', 'south', 'east') else f'routes_{host}'
        message = f'On app{host}, /srv/routes/{route} is a directory with mode 0750 : ✗ [DQ:{marker}]'
        lines.extend([
            f'if ! test -d {path} || ! test "$(stat -c %a {path} 2>/dev/null)" = 750; then',
            "printf '%s\n' " + shlex.quote(message),
            'failed=1', 'fi',
        ])
    lines.append('exit "$failed"')
    try:
        result = subprocess.run(
            ['ssh', '-n', '-o', 'BatchMode=yes', '-p', '2222',
             f'root@app{host}-' + sys.argv[1].removeprefix('dq-'), '\n'.join(lines)],
            text=True, capture_output=True, timeout=5,
        )
        if result.stdout:
            print(result.stdout, end='')
        if result.returncode:
            failed = True
            if not result.stdout:
                print(f'Could not verify route directories on app{host}: ✗ [DQ:routes_{host}]')
    except (OSError, subprocess.TimeoutExpired):
        failed = True
        print(f'Could not verify route directories on app{host}: ✗ [DQ:routes_{host}]')
sys.exit(int(failed))
DQ_ROUTES
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify the route directories: ✗ [DQ:probe_0_0]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
