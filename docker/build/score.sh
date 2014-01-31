#!/bin/bash

set -e

pwd=`pwd -P`

username="$1"
shift

uid="$1"
shift

reader_pipe=/srv/mount/reader_pipe
writer_pipe=/srv/mount/writer_pipe

# Prepare the pipes
exec 3<"$reader_pipe"
exec 4>"$writer_pipe"

rm "$reader_pipe" "$writer_pipe"

sync_with_master() {
    # write to the master, letting them know we're waiting
    echo -n >&4 "$1"
    # read from the master, who has now let us know it's done, and
    # execute what we're given.
    read -d "$(echo -e '\t')" cmd <&3
    eval "$cmd" >> /var/log/sync_with_master.log 2>&1 </dev/null
}

# Set up filesystem
cat > /etc/passwd <<EOF
root:x:0:0:Second Best User Ever:/root:/bin/bash
${username}:x:${uid}:${uid}:Best User Ever:${pwd}:/bin/bash
EOF

cat > /etc/shadow <<EOF
root:*:16000:0:99999:7:::
${username}:*:16000:0:99999:7:::
EOF

cat > /etc/group <<EOF
root:x:0:
${username}:x:${uid}:
EOF

sync_with_master a

(
  exec 3>&-
  exec 4>&-
  exec su "$username" -c 'exec "$@"' -- score.sh "$@"
) && exit=$? || exit=$?

sync_with_master "$exit
" # THIS NEWLINE IS IMPORTANT
