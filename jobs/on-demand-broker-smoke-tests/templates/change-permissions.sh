#!/bin/bash -e

[ -z "$DEBUG" ] || set -x

ensure_directories_are_not_world_readable() {
  chmod 750 "/var/vcap/jobs/on-demand-broker-smoke-tests"
  chown -LR vcap:vcap "/var/vcap/jobs/on-demand-broker-smoke-tests"
}

ensure_directories_are_not_world_readable
