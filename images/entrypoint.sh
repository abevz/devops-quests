#!/bin/bash
set -euo pipefail
case "${1:-workstation}" in
  workstation) exec sleep infinity ;;
  target)
    ssh-keygen -A
    mkdir -p /root/.ssh /srv/site
    chmod 700 /root/.ssh
    cp /run/dq/authorized_keys /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    printf 'unconfigured\n' > /srv/site/message
    dq-service start
    exec /usr/sbin/sshd -D -e -p 2222 -o PasswordAuthentication=no -o PermitRootLogin=prohibit-password -o UsePAM=no
    ;;
  *) exec "$@" ;;
esac
