#!/bin/bash
set -euo pipefail
# Docker --internal omits the default route. Upstream kind's DNS rewrite needs
# a non-loopback address. Its own node address is reachable by game pods and
# keeps Docker DNS DNAT entirely inside this network namespace.
node_ip=$(ip -4 -o addr show dev eth0 | awk '{split($4,a,"/"); print a[1]; exit}')
test -n "$node_ip"
printf '\n%s host.docker.internal\n' "$node_ip" >> /etc/hosts
exec /usr/local/bin/entrypoint "$@"
