#!/bin/bash
set -e

source /var/vcap/packages/golang-1.10-linux/bosh/runtime.env

# TODO - what are these????
. /var/vcap/jobs/on-demand-broker-smoke-tests/bin/change-permissions
. /var/vcap/jobs/on-demand-broker-smoke-tests/bin/permissions-test

export GOPATH=/var/vcap/packages/cf-rabbitmq-smoke-tests
# export GOROOT=/var/vcap/packages/golang
export PATH=/var/vcap/packages/cf-cli-6-linux/bin:$GOPATH/bin:$GOROOT/bin:$PATH
export REPO_NAME=github.com/pivotal-cf/cf-rabbitmq-smoke-tests
export REPO_DIR=${GOPATH}/src/${REPO_NAME}

export CONFIG_PATH=/var/vcap/jobs/on-demand-broker-smoke-tests/config.json

export CF_DIAL_TIMEOUT=11

pushd ${REPO_DIR}
  echo "Running smoke tests"
	go install -v github.com/onsi/ginkgo/ginkgo
	ginkgo -v --trace -randomizeSuites=true -randomizeAllSpecs=true -keepGoing=true -failOnPending tests
popd

# 1. download src folder of CF CLI
# 2. bosh add-blob cf/cf-cli.tar.gz ~/Downloads/cf...
# 3. add a package cf cli where we untar and compile the CF CLI
# 4. use it in run.sh

