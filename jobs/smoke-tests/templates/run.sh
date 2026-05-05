#!/bin/bash
set -e

. /var/vcap/jobs/smoke-tests/bin/change-permissions
. /var/vcap/jobs/smoke-tests/bin/permissions-test

export CONFIG_ENV_PATH=/var/vcap/jobs/smoke-tests/config/config.env
exec /var/vcap/packages/smoke-tests-runner/bin/run
