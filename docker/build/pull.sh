#!/bin/sh

set -ex

cd "$(dirname "$0")"
docker pull colossus1.cluster:9001/stripectf/runtime
