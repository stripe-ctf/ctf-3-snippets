#!/bin/bash

set -eu

trap 'echo >&2 init.sh ERROR' EXIT

username="$1"
shift

uid="$1"
shift

timeout="$1"
shift

level="$1"
shift

# Set up filesystem
cat > /etc/passwd <<EOF
root:x:0:0:Second Best User Ever:/root:/bin/bash
${username}:x:${uid}:10000:Best User Ever:/home/${username}:/bin/bash
nobody:x:65534:65534:nobody:/nonexistent:/bin/bash
helper:x:10:65533:helper:/helper:/bin/bash
EOF

cat > /etc/shadow <<EOF
root:*:16000:0:99999:7:::
${username}:*:16000:0:99999:7:::
nobody:*:16000:0:99999:7:::
helper:*:16000:0:99999:7:::
EOF

cat > /etc/group <<EOF
root:x:0:
ctf:x:10000:
nogroup:x:65534:
helpergrp:x:65533:
EOF

# bring up loopback interface
ifup lo

echo >&2 "Container $HOSTNAME's init has come up; will time out in ${timeout}s."

trap - EXIT

# Coordinate with master
echo "booted"
read -t "$timeout" _ || echo "Container timed out after ${timeout}s."
