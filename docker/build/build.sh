#!/bin/sh

set -eu

if [ $# != 0 ]; then
    echo "NEW USAGE (builds v0 and public version): $(basename "$0")"
    exit 1
fi

tag=v0
all="-a"

set -x
cd "$(dirname "$0")"
docker build -t colossus1.cluster:9001/stripectf/runtime:$tag .

if [ "$all" = "-a" ]; then
    docker build -t stripectf/runtime .
fi
