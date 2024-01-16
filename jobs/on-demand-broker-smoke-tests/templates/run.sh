#!/bin/bash
set -ex

export GOROOT=$(readlink -nf /var/vcap/packages/cf-rabbitmq-smoke-tests-golang)
export GOPATH=/var/vcap/packages/cf-rabbitmq-smoke-tests
export PATH=/var/vcap/packages/cf-cli-7-linux/bin:$GOPATH/bin:$GOROOT/bin:$PATH

export GOCACHE=$PWD/cache

export PACKAGE_DIR=${GOPATH}/src/rabbitmq-smoke-tests

export CF_DIAL_TIMEOUT=11
export CF_HOME="/tmp/cf_home"
mkdir -p "$CF_HOME"

export CONFIG_PATH="/var/vcap/jobs/on-demand-broker-smoke-tests/config.json"
export CGO_ENABLED=0
export SMOKE_TESTS_TIMEOUT=1h

pushd ${PACKAGE_DIR}
  echo "Running on-demand smoke tests"
  # Disbale Go modules and cgo to avoid issue https://github.com/golang/go/issues/26988
  CGO_ENABLED=0 GO111MODULE=off ginkgo -v --trace --randomize-suites --randomize-all --keep-going --timeout="$SMOKE_TESTS_TIMEOUT" --fail-on-pending tests
popd

