set -euo pipefail
cd ~/quest
source platform.env
cd repository
git remote add origin "$GIT_URL"
printf 'retired
' > notice.txt
git add notice.txt
git commit -m 'Record initial station notice'
git push -u origin main
git rev-parse HEAD > ../baseline-commit
git switch -c release-candidate
printf 'north-41
' > notice.txt
git add notice.txt
git commit -m 'Prepare north station release'
git push -u origin release-candidate
git switch main
cd ..
