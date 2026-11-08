set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_BOSS'
import json, os, re, subprocess, sys
from pathlib import Path
from decimal import Decimal

def require(good, marker):
    if not good:raise AssertionError(marker)

try:
    import yaml
    from functools import lru_cache
    @lru_cache(maxsize=1)
    def inventory():return json.loads(subprocess.check_output(['ansible-inventory','--list'],text=True,timeout=3))
    def members(name,seen=None):
        seen=set() if seen is None else seen
        if name in seen:return set()
        seen.add(name);item=inventory().get(name,{})
        result=set(item.get('hosts',[]))
        for child in item.get('children',[]):result |= members(child,seen)
        return result

    def one_at_a_time(value, hosts):
        batches=value if isinstance(value,list) else [value]
        if not batches or value is None:return False
        if all(type(v) is int and v==1 or isinstance(v,str) and v=='1' for v in batches):return True
        # Resolve the actual supplied host pattern instead of assuming fleet size.
        selected=subprocess.check_output(['ansible','all','--list-hosts'],text=True,timeout=3)
        all_hosts=set(line.strip() for line in selected.splitlines()[1:] if line.strip())
        if hosts in ('fleet',['fleet']):total=len(members('fleet'))
        elif isinstance(hosts,list):total=len(set(hosts)&all_hosts)
        elif isinstance(hosts,str) and hosts in all_hosts:total=1
        else:return False
        if total<1:return False
        remaining=total;i=0
        while remaining:
            item=batches[min(i,len(batches)-1)]
            if type(item) is int:number=item
            elif isinstance(item,str) and re.fullmatch(r'[0-9]+%',item):number=int(int(item[:-1])*total/100) or 1
            elif isinstance(item,str) and re.fullmatch(r'[0-9]+',item):number=int(item)
            else:return False
            actual=remaining if number<=0 else min(number,remaining)
            if actual!=1:return False
            remaining-=actual;i+=1
        return True
    plays=yaml.safe_load(Path('rollout.yml').read_text())
    require(isinstance(plays,list) and bool(plays) and all(isinstance(p,dict) and one_at_a_time(p.get('serial'),p.get('hosts')) for p in plays),'serial')

except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'serial'
    print('Required result is missing: ✗ [DQ:'+marker+']')
    sys.exit(1)
DQ_BOSS
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_0]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
if ! ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/maintenance.txt)" = north-40'; then printf '%s\n' 'app1 /srv/site/maintenance.txt = north-40: ✗ [DQ:maintenance_1]' >&2; failed=1; fi
if ! ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/maintenance.txt)" = north-40'; then printf '%s\n' 'app2 /srv/site/maintenance.txt = north-40: ✗ [DQ:maintenance_2]' >&2; failed=1; fi
if ! ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/maintenance.txt)" = north-40'; then printf '%s\n' 'app3 /srv/site/maintenance.txt = north-40: ✗ [DQ:maintenance_3]' >&2; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
