#!/bin/bash

set -eux

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
PACKAGE_DIR="$DIR/../"

pushd $PACKAGE_DIR
    GO111MODULE=on go mod tidy
    GO111MODULE=on go get -t -u all
    GO111MODULE=on go mod vendor
popd
