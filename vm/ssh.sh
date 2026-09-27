#!/bin/sh
# ssh into the running VM as root: vm/ssh.sh [command...]
cd "$(dirname "$0")"
exec ssh -q -i out/id_ed25519 -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@127.0.0.1 "$@"
