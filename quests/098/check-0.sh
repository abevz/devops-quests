set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
failed=0
original=$(cat /run/dq/facts/0/original-id 2>/dev/null || true)
actual=$(tofu output -raw managed_id 2>/dev/null || true)
if ! test -n "$original" || ! test "$actual" = "$original"; then printf '%s\n' 'managed_id = original-id: ✗ [DQ:managed_id]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
dq_property_failed=0
set +e
(
set -e
dq_property_failed=0
set +e
(
set -e
failed=0
if ! test "$(cat managed-route.txt 2>/dev/null)" = north-98; then printf '%s\n' 'managed-route.txt = north-98: ✗ [DQ:route_file]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || dq_property_failed=1
(
set -e
failed=0
require() { local message=$1; shift; if ! "$@" >/dev/null 2>&1; then printf '%s\n' "$message: ✗"; failed=1; fi; }
check_jq() { jq -e "$1" <<<"$2"; }
contract=$(tofu output -json contract 2>/dev/null || true)
require 'tofu output contract route = north-98 [DQ:contract_output]' check_jq '.route=="north-98"' "$contract"
require 'contract.json route = north-98 [DQ:contract_file]' jq -e '.route=="north-98"' contract.json
exit "$failed"
)
[ $? -eq 0 ] || dq_property_failed=1
(
set -e
failed=0
for n in 1 2 3; do
  host="app${n}-${DQ_NAMESPACE#dq-}"
  if ! test "$(curl -fsS --max-time 3 "http://$host:8080" 2>/dev/null)" = north-98; then printf '%s\n' "$host:8080 = north-98: ✗ [DQ:http_$n]"; failed=1; fi
done
exit "$failed"
)
[ $? -eq 0 ] || dq_property_failed=1
(
set -e
failed=0
require() { local message=$1; shift; if ! "$@" >/dev/null 2>&1; then printf '%s\n' "$message: ✗"; failed=1; fi; }
check_jq() { jq -e "$1" <<<"$2"; }
route=$(kubectl get configmap route -o json 2>/dev/null || true)
require 'configmap/route route = north-98 [DQ:configmap]' check_jq '.data.route=="north-98"' "$route"
exit "$failed"
)
[ $? -eq 0 ] || dq_property_failed=1
(
set -e
failed=0
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -c worker -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-98; then printf '%s\n' 'board:8080 = north-98: ✗ [DQ:board_http]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || dq_property_failed=1
set -e
test "$dq_property_failed" -eq 0
)
[ $? -eq 0 ] || dq_property_failed=1
(
set -e
failed=0
python3 -I - <<'DQ_REFERENCE'
import json
import os
import stat
import sys
from pathlib import Path


def read_json(path, successful=True):
    if not successful:
        return None
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return None


def resource_records(document, section='values'):
    if not isinstance(document, dict):
        return []
    values = document.get(section)
    root = values.get('root_module') if isinstance(values, dict) else None
    if not isinstance(root, dict):
        return []
    records = []
    pending = [root]
    while pending:
        module = pending.pop()
        resources = module.get('resources') or []
        children = module.get('child_modules') or []
        if not isinstance(resources, list) or not isinstance(children, list):
            return []
        for resource in resources:
            if not isinstance(resource, dict):
                return []
            records.append((module.get('address'), resource))
        if not all(isinstance(child, dict) for child in children):
            return []
        pending.extend(children)
    return records


def same_target(value, expected, existing=False):
    if not isinstance(value, str) or not value:
        return False
    try:
        expanded = os.path.expanduser(value)
        parent, leaf = os.path.split(expanded)
        if leaf in ('', '.', '..'):
            return False
        # Validate raw traversal before pathlib normalizes it: file/.. and
        # absent/../file are not usable aliases of an existing file.
        if not stat.S_ISDIR(os.stat(parent or '.').st_mode):
            return False
        target = Path(expected)
        if existing or target.exists():
            if not stat.S_ISREG(os.stat(expanded).st_mode):
                return False
            return Path(expanded).resolve(strict=True) == target.resolve(strict=True)
        candidate = Path(parent or '.').resolve(strict=True) / leaf
        return candidate == target.parent.resolve(strict=True) / target.name
    except (OSError, RuntimeError, ValueError):
        return False


def file_resources(records, filename, in_module=False):
    found = []
    for module, resource in records:
        values = resource.get('values')
        if (resource.get('mode') == 'managed' and resource.get('type') == 'local_file'
                and isinstance(values, dict) and same_target(values.get('filename'), filename)
                and (not in_module or isinstance(module, str) and bool(module))):
            found.append((module, resource))
    return found


def number_is(value, expected):
    return type(value) in (int, float) and value == expected

import json
import re
from pathlib import Path


class UnsupportedForwarder(ValueError):
    pass


def hcl_tokens(source):
    """Tokenize only; strings/comments/heredocs never become declarations."""
    length = len(source)

    def comment(position):
        if source.startswith('/*', position):
            end = source.find('*/', position + 2)
            if end < 0:
                raise UnsupportedForwarder('Unterminated comment')
            return end + 2
        end = source.find('\n', position)
        return length if end < 0 else end

    def heredoc(position):
        end = source.find('\n', position)
        if end < 0:
            raise UnsupportedForwarder('Unterminated heredoc')
        intro = source[position:end].rstrip('\r')
        match = re.fullmatch(r'<<(-?)([A-Za-z_][A-Za-z0-9_-]*)[ \t]*', intro)
        if not match:
            raise UnsupportedForwarder('Unsupported heredoc marker')
        indented, marker = match.groups()
        position = end + 1
        while position < length:
            end = source.find('\n', position)
            end = length if end < 0 else end
            line = source[position:end].rstrip('\r')
            if line.strip() == marker:
                # Ambiguous whitespace is rejected rather than exposing string
                # contents as executable HCL declarations.
                if line != marker and (not indented or line.lstrip(' \t') != marker):
                    raise UnsupportedForwarder('Unsupported heredoc delimiter whitespace')
                return end
            position = end + 1
        raise UnsupportedForwarder('Unterminated heredoc')

    def quoted(position):
        position += 1
        while position < length:
            if source[position] == '\\':
                position += 2
            elif source.startswith(('$${', '%%{'), position):
                position += 3
            elif source.startswith(('${', '%{'), position):
                position = interpolation(position + 2)
            elif source[position] == '"':
                return position + 1
            else:
                position += 1
        raise UnsupportedForwarder('Unterminated string')

    def interpolation(position):
        depth = 1
        while position < length:
            if source[position] == '"':
                position = quoted(position)
            elif source[position] == '#' or source.startswith(('//', '/*'), position):
                position = comment(position)
            elif source.startswith('<<', position):
                position = heredoc(position)
            elif source[position] == '{':
                depth += 1
                position += 1
            elif source[position] == '}':
                depth -= 1
                position += 1
                if not depth:
                    return position
            else:
                position += 1
        raise UnsupportedForwarder('Unterminated interpolation')

    tokens = []
    position = 0
    while position < length:
        character = source[position]
        if character in ' \t\r':
            position += 1
        elif character == '\n':
            tokens.append(('newline', '\n'))
            position += 1
        elif character == '#' or source.startswith(('//', '/*'), position):
            position = comment(position)
        elif character == '"':
            end = quoted(position)
            tokens.append(('string', source[position:end]))
            position = end
        elif source.startswith('<<', position):
            end = heredoc(position)
            tokens.append(('opaque', source[position:end]))
            position = end
        elif character.isalpha() or character == '_':
            end = position + 1
            while end < length and (source[end].isalnum() or source[end] in '_-'):
                end += 1
            tokens.append(('word', source[position:end]))
            position = end
        else:
            tokens.append(('punctuation', character))
            position += 1
    return tokens


def forward_reference(tokens):
    """Accept only transparent forwarding, never an unused conditional ref."""
    tokens = [token for token in tokens if token[0] != 'newline']
    position = 0
    wrappers = {'trimspace', 'chomp', 'tostring', 'sensitive', 'nonsensitive'}

    def expression():
        nonlocal position
        if position >= len(tokens):
            raise UnsupportedForwarder('Missing expression')
        kind, text = tokens[position]
        if text == '(':
            position += 1
            result = expression()
            if position >= len(tokens) or tokens[position][1] != ')':
                raise UnsupportedForwarder('Missing parenthesis')
            position += 1
            return result
        if kind == 'string':
            position += 1
            if not (text.startswith('"${') and text.endswith('}"')):
                raise UnsupportedForwarder('Literal is not a reference')
            return forward_reference(hcl_tokens(text[3:-2]))
        if kind != 'word':
            raise UnsupportedForwarder('Not a forwarding expression')
        position += 1
        if position < len(tokens) and tokens[position][1] == '(':
            if text not in wrappers:
                raise UnsupportedForwarder('Opaque function')
            position += 1
            result = expression()
            if position >= len(tokens) or tokens[position][1] != ')':
                raise UnsupportedForwarder('Not a unary transparent wrapper')
            position += 1
            return result
        result = text
        while position < len(tokens):
            if tokens[position][1] == '.':
                position += 1
                if position >= len(tokens) or tokens[position][0] != 'word':
                    raise UnsupportedForwarder('Invalid traversal')
                result += '.' + tokens[position][1]
                position += 1
            elif tokens[position][1] == '[':
                position += 1
                if position >= len(tokens):
                    raise UnsupportedForwarder('Missing lookup index')
                if tokens[position][0] == 'string':
                    name = json.loads(tokens[position][1])
                    if not isinstance(name, str):
                        raise UnsupportedForwarder('Invalid lookup name')
                    # local["name"] and local.name name the same local; resource
                    # instance keys stay bracketed, distinct from attributes.
                    if result == 'local' and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_-]*', name):
                        result += '.' + name
                    else:
                        result += '[' + json.dumps(name, ensure_ascii=False) + ']'
                    position += 1
                else:
                    digits = ''
                    while position < len(tokens) and re.fullmatch(r'[0-9]', tokens[position][1]):
                        digits += tokens[position][1]
                        position += 1
                    if not digits:
                        raise UnsupportedForwarder('Only literal instance indices are certified')
                    result += '[' + str(int(digits)) + ']'
                if position >= len(tokens) or tokens[position][1] != ']':
                    raise UnsupportedForwarder('Invalid lookup')
                position += 1
            else:
                break
        return result

    result = expression()
    if position != len(tokens):
        raise UnsupportedForwarder('Opaque expression')
    return result


def block_attributes(tokens):
    attributes = {}
    position = 0
    while position < len(tokens):
        if tokens[position][0] == 'newline':
            position += 1
            continue
        if (position + 1 >= len(tokens) or tokens[position][0] != 'word'
                or tokens[position + 1][1] != '='):
            raise UnsupportedForwarder('Unsupported block declaration')
        name = tokens[position][1]
        position += 2
        start = position
        depth = 0
        while position < len(tokens):
            text = tokens[position][1]
            if tokens[position][0] == 'newline' and not depth:
                break
            if text in ('(', '[', '{'):
                depth += 1
            elif text in (')', ']', '}'):
                depth -= 1
                if depth < 0:
                    raise UnsupportedForwarder('Unbalanced expression')
            position += 1
        if name in attributes:
            raise UnsupportedForwarder('Duplicate attribute')
        attributes[name] = tokens[start:position]
    return attributes


def module_forward_definitions(directory, output_name):
    local_values = {}
    output = None

    def add_local(name, value):
        if name in local_values:
            raise UnsupportedForwarder('Duplicate local definition')
        local_values[name] = value

    def json_expression(value):
        if isinstance(value, str) and value.startswith('${') and value.endswith('}'):
            return hcl_tokens(value[2:-1])
        raise UnsupportedForwarder('Not an expression template')

    for path in sorted(Path(directory).iterdir()):
        if path.name.startswith(('.', '#')) or path.name.endswith('~'):
            continue
        if path.name.endswith('.tf.json'):
            data = json.loads(path.read_text())
            blocks = data.get('locals', [])
            blocks = [blocks] if isinstance(blocks, dict) else blocks
            for block in blocks:
                for name, value in block.items():
                    try:
                        add_local(name, json_expression(value))
                    except UnsupportedForwarder:
                        add_local(name, [('opaque', '')])
            block = data.get('output', {}).get(output_name)
            if block is not None:
                if output is not None:
                    raise UnsupportedForwarder('Duplicate output')
                output = json_expression(block['value'])
        elif path.name.endswith('.tf'):
            tokens = hcl_tokens(path.read_text())
            position = 0
            while position < len(tokens):
                if tokens[position][0] == 'newline':
                    position += 1
                    continue
                start = position
                while position < len(tokens) and tokens[position][1] != '{':
                    position += 1
                if position == len(tokens):
                    raise UnsupportedForwarder('Incomplete top-level block')
                header = [token for token in tokens[start:position] if token[0] != 'newline']
                position += 1
                body_start = position
                depth = 1
                while position < len(tokens) and depth:
                    if tokens[position][1] == '{':
                        depth += 1
                    elif tokens[position][1] == '}':
                        depth -= 1
                    position += 1
                if depth:
                    raise UnsupportedForwarder('Unterminated block')
                body = tokens[body_start:position - 1]
                if header == [('word', 'locals')]:
                    for name, value in block_attributes(body).items():
                        add_local(name, value)
                elif (len(header) == 2 and header[0] == ('word', 'output')
                      and ((header[1][0] == 'string' and json.loads(header[1][1]) == output_name)
                           or header[1] == ('word', output_name))):
                    if output is not None:
                        raise UnsupportedForwarder('Duplicate output')
                    output = block_attributes(body)['value']
    if output is None:
        raise UnsupportedForwarder('Missing output definition')
    return output, local_values


def module_forwards(directory, references, endpoint, output_name='route'):
    try:
        expression, definitions = module_forward_definitions(directory, output_name)
        reference = forward_reference(expression)
        known = {forward_reference(hcl_tokens(value)) for value in references if isinstance(value, str)}
        if reference not in known:
            return False
        endpoint = forward_reference(hcl_tokens(endpoint))
        seen = set()
        while reference != endpoint:
            if not reference.startswith('local.') or reference.count('.') != 1:
                return False
            name = reference.split('.', 1)[1]
            if name in seen or name not in definitions:
                return False
            seen.add(name)
            reference = forward_reference(definitions[name])
        return True
    except (OSError, ValueError, KeyError, TypeError):
        return False

import subprocess
import tempfile

def verify_forwarding():
    with tempfile.NamedTemporaryFile() as saved:
        result = subprocess.run(['tofu', 'plan', '-input=false', '-detailed-exitcode', '-no-color', '-out=' + saved.name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode not in (0, 2):
            return False
        result = subprocess.run(['tofu', 'show', '-json', saved.name], capture_output=True, text=True)
        if result.returncode != 0:
            return False
        try:
            plan = json.loads(result.stdout)
            call = plan['configuration']['root_module']['module_calls']['station']
            refs = call['module']['outputs']['route']['expression']['references']
            source = call['source']
        except (ValueError, KeyError, TypeError):
            return False
        # Read the current local module source, not an outdated cached module copy.
        if not isinstance(source, str) or not source.startswith(('./', '../', '/')):
            return False
        producers = file_resources(resource_records(plan, 'planned_values'), 'managed-route.txt', in_module=True)
        for module, resource in producers:
            if module != 'module.station':
                continue
            address = resource.get('address', '')
            prefix = 'module.station.'
            if not address.startswith(prefix):
                continue
            endpoint = address[len(prefix):] + '.content'
            if module_forwards(source, refs, endpoint):
                return True
        return False

if not verify_forwarding():
    print('The module output must forward the managed producer file contents: ✗ [DQ:reference]')
    sys.exit(1)
DQ_REFERENCE
)
[ $? -eq 0 ] || dq_property_failed=1
set -e
test "$dq_property_failed" -eq 0
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
failed=0
for n in 1 2 3; do
  host="app${n}-${DQ_NAMESPACE#dq-}"
  result=$(timeout 4s ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 "root@$host" 'actual=$(sha256sum /srv/site/message 2>/dev/null | cut -d " " -f 1); if test "$actual" = bdbf510116b9f7963361e3e7b5f3621586fc01e42d2dc0aac1b97a229b1160fc || test "$actual" = 9348964429c827929d2d5467b62a30c15c416b43714c5c8a6471d60804d2cfbf; then printf "content-ok\n"; fi; if test "$(stat -c %a /srv/site/message 2>/dev/null)" = 644; then printf "mode-ok\n"; fi' 2>/dev/null || true)
  if ! grep -Fxq content-ok <<<"$result"; then printf '%s\n' "$host /srv/site/message = north-98: ✗ [DQ:content_$n]"; failed=1; fi
  if ! grep -Fxq mode-ok <<<"$result"; then printf '%s\n' "$host /srv/site/message mode = 644: ✗ [DQ:mode_$n]"; failed=1; fi
done
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
plan=$(mktemp)
trap 'rm -f "$plan"' EXIT
if ! tofu plan -input=false -detailed-exitcode -no-color -out="$plan" >/dev/null 2>&1; then printf '%s\n' 'tofu plan exits 0: ✗ [DQ:plan]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
failed=0
require() { local message=$1; shift; if ! "$@" >/dev/null 2>&1; then printf '%s\n' "$message: ✗"; failed=1; fi; }
check_jq() { jq -e "$1" <<<"$2"; }
board=$(kubectl get deployment board -o json 2>/dev/null || true)
require 'deployment/board replicas = 1 [DQ:replicas]' check_jq '.spec.replicas==1' "$board"
if ! check_jq '[.spec.template.spec.containers[] | select(.name=="worker")] | length==1 and (.[0].env | [.[] | select(.name=="ROUTE")] | length==1 and (.[0] | ((has("value")|not) or .value=="") and .valueFrom.configMapKeyRef.name=="route" and .valueFrom.configMapKeyRef.key=="route"))' "$board" >/dev/null 2>&1 || ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -c worker -- printenv ROUTE 2>/dev/null)" = north-98; then
  printf '%s\n' 'The running worker must receive north-98 from the supplied configuration without an embedded value: ✗ [DQ:board_env]'; failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
