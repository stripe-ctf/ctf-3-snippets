#!/bin/sh

set -ex

if [ $# != 0 ]; then
    echo "NEW USAGE (autopushes to public): $0"
fi

cd "$(dirname "$0")"
docker push colossus1.cluster:9001/stripectf/runtime
docker push stripectf/runtime

