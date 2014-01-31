#!/bin/sh

set -ex

export PATH="$PATH":/usr/local/go/bin
export GOPATH=/skeleton/go

# Manually specify deps for level4. There are probably others that should be here?

go get -d github.com/goraft/raft
go get -d code.google.com/p/goprotobuf
go get -d github.com/gorilla/mux
