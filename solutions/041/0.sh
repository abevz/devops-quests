set -euo pipefail
cd ~/quest
source platform.env
cd repository
git cherry-pick release-candidate
git push origin main
