set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
tofu state list | grep -Fx terraform_data.directory
tofu state list | grep -Fx terraform_data.marker
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
python3 -I - <<'DQ_PROPERTY'
import json
import re
import sys
from pathlib import Path


def dependency_edges(source):
    tokens = []
    position = 0
    while position < len(source):
        character = source[position]
        if character.isspace():
            position += 1
        elif source.startswith('//', position) or character == '#':
            end = source.find('\n', position)
            position = len(source) if end < 0 else end
        elif source.startswith('/*', position):
            end = source.find('*/', position + 2)
            if end < 0:
                return {}
            position = end + 2
        elif character == '"':
            start = position
            position += 1
            while position < len(source):
                if source[position] == '\\':
                    position += 2
                elif source[position] == '"':
                    position += 1
                    break
                else:
                    position += 1
            try:
                name = json.loads(source[start:position])
            except ValueError:
                return {}
            if name.startswith('[root] '):
                name = name[len('[root] '):]
            name = re.sub(r' \(expand\)$', '', name)
            tokens.append(('node', name))
        elif source.startswith('->', position):
            tokens.append(('arrow', '->'))
            position += 2
        else:
            # Preserve barriers; attribute labels cannot become graph edges.
            tokens.append(('other', character))
            position += 1
    edges = {}
    for left, arrow, right in zip(tokens, tokens[1:], tokens[2:]):
        if left[0] == right[0] == 'node' and arrow[0] == 'arrow':
            edges.setdefault(left[1], set()).add(right[1])
    return edges


def ordered_after(edges, later, earlier):
    pending = [later]
    seen = set()
    while pending:
        node = pending.pop()
        if node in seen:
            continue
        seen.add(node)
        for dependency in edges.get(node, ()):
            if dependency == earlier:
                return True
            pending.append(dependency)
    return False

import subprocess
result = subprocess.run(['tofu', 'graph'], capture_output=True, text=True)
sys.exit(0 if result.returncode == 0 and ordered_after(dependency_edges(result.stdout), 'terraform_data.marker', 'terraform_data.directory') else 1)
DQ_PROPERTY
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_1]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
test -f work/.prepared
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(cat work/route.txt)" = north
)
[ $? -eq 0 ] || failed=1
(
set -e
tofu plan -input=false -detailed-exitcode -no-color >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
