set -euo pipefail
cd ~/quest
failed=0
if ! test "$(cat release.txt 2>/dev/null)" = release-20; then printf '%s\n' 'release.txt = release-20: ✗ [DQ:file]'; failed=1; fi
if ! test "$(tofu output -raw release 2>/dev/null)" = release-20; then printf '%s\n' 'tofu output release = release-20: ✗ [DQ:output]'; failed=1; fi
if ! tofu state list 2>/dev/null | grep -Fx local_file.release >/dev/null; then printf '%s\n' 'tofu state contains local_file.release: ✗ [DQ:state]'; failed=1; fi
if ! tofu plan -input=false -detailed-exitcode -no-color >/dev/null 2>&1; then printf '%s\n' 'tofu plan exits 0: ✗ [DQ:plan]'; failed=1; fi
exit "$failed"
