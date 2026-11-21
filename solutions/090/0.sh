set -euo pipefail
cd ~/quest
(cd recovery && sha256sum -c checkpoint.sha256)
backup_copy=$(mktemp -d)
trap 'rm -r -- "$backup_copy"' EXIT
cp recovery/checkpoint.tfstate "$backup_copy/checkpoint.tfstate"
for address in local_file.release terraform_data.release_record; do
    tofu state mv -state="$backup_copy/checkpoint.tfstate" -state-out=terraform.tfstate "$address" "$address"
done
tofu apply -auto-approve -input=false -no-color
