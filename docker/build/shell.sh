#!/bin/bash

set -eu

username="$1"
shift

cwd="$1"
shift

cd "$cwd"

exec su "$username" -c '
export CTF_BUILD_ENV=true
export PATH="$PATH:$HOME/go/bin:/usr/local/go/bin:/usr/local/node/bin:/ctf3/level3/"
export GOPATH="/skeleton/go"
exec "$@"
' -- "Couldn't run command" "$@"
