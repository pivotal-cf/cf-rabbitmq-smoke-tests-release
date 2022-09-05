#!/bin/bash
set -e

. /var/vcap/jobs/smoke-tests/bin/change-permissions
. /var/vcap/jobs/smoke-tests/bin/permissions-test

export GOROOT=$(readlink -nf /var/vcap/packages/cf-rabbitmq-smoke-tests-golang)
export GOPATH=/var/vcap/packages/cf-rabbitmq-smoke-tests
export PATH=/var/vcap/packages/cf-cli-7-linux/bin:$GOPATH/bin:$GOROOT/bin:$PATH
export PACKAGE_DIR=${GOPATH}/src/rabbitmq-smoke-tests

export GOCACHE=$PWD/cache

export CONFIG_PATH=/var/vcap/jobs/smoke-tests/config.json

export CF_DIAL_TIMEOUT=11
export SMOKE_TESTS_TIMEOUT=1h

pushd ${PACKAGE_DIR}
  echo "Running multitenant smoke tests"
  # Disbale Go modules and cgo to avoid issue https://github.com/golang/go/issues/26988
  CGO_ENABLED=0 GO111MODULE=off ginkgo -v --trace -randomizeSuites=true -randomizeAllSpecs=true -keepGoing=true --timeout="$SMOKE_TESTS_TIMEOUT" -failOnPending tests
popd
