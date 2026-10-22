set -euo pipefail
cd ~/quest
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/release.txt)" = release-89 && test "$(stat -c %a /srv/site/reader.token)" = 600 && test "$(cat /srv/site/reader.token)" = game-only-reader'
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/release.txt)" = release-89 && test "$(stat -c %a /srv/site/reader.token)" = 600 && test "$(cat /srv/site/reader.token)" = game-only-reader'
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/release.txt)" = release-89 && test "$(stat -c %a /srv/site/reader.token)" = 600 && test "$(cat /srv/site/reader.token)" = game-only-reader'
