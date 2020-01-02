#!/bin/bash

set -euo pipefail

BASEDIR=$(dirname "$0")

pushd "$BASEDIR"/../
  bundle install
  rspec tests/templates/
popd
