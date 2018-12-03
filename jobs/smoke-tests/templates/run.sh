#!/bin/bash
set -e

. /var/vcap/jobs/smoke-tests/bin/change-permissions
. /var/vcap/jobs/smoke-tests/bin/permissions-test

export GOROOT=$(readlink -nf /var/vcap/packages/cf-rabbitmq-smoke-tests-golang)
export GOPATH=/var/vcap/packages/cf-rabbitmq-smoke-tests
export PATH=/var/vcap/packages/cf-cli-6-linux/bin:$GOPATH/bin:$GOROOT/bin:$PATH
export PACKAGE_DIR=${GOPATH}/src/rabbitmq-smoke-tests

export CONFIG_PATH=/var/vcap/jobs/smoke-tests/config.json

export CF_DIAL_TIMEOUT=11
export SMOKE_TESTS_TIMEOUT=1h

pushd ${PACKAGE_DIR}
  echo "Running multitenant smoke tests"
  go install -v github.com/onsi/ginkgo/ginkgo
  ginkgo -v --trace -randomizeSuites=true -randomizeAllSpecs=true -keepGoing=true --timeout="$SMOKE_TESTS_TIMEOUT" -failOnPending tests
popd
