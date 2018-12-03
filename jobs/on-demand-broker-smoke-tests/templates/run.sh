#!/bin/bash
set -ex

export GOROOT=$(readlink -nf /var/vcap/packages/cf-rabbitmq-smoke-tests-golang)
export GOPATH=/var/vcap/packages/cf-rabbitmq-smoke-tests
export PATH=/var/vcap/packages/cf-cli-6-linux/bin:$GOPATH/bin:$GOROOT/bin:$PATH

export PACKAGE_DIR=${GOPATH}/src/rabbitmq-smoke-tests

export CF_DIAL_TIMEOUT=11
export CF_HOME="/tmp/cf_home"
mkdir -p "$CF_HOME"

export CONFIG_PATH="/var/vcap/jobs/on-demand-broker-smoke-tests/config.json"
export CGO_ENABLED=0
export SMOKE_TESTS_TIMEOUT=1h

pushd ${PACKAGE_DIR}
  echo "Running on-demand smoke tests"
  go install -v github.com/onsi/ginkgo/ginkgo
  ginkgo -v --trace -randomizeSuites=true -randomizeAllSpecs=true -keepGoing=true --timeout="$SMOKE_TESTS_TIMEOUT" -failOnPending tests
popd

