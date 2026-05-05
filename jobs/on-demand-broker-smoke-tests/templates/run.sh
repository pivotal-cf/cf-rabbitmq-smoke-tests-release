#!/bin/bash
set -e

export CONFIG_ENV_PATH=/var/vcap/jobs/on-demand-broker-smoke-tests/config/config.env
exec /var/vcap/packages/smoke-tests-runner/bin/run
