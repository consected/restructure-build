#!/bin/bash
# Generalized, host-only replacement for env-setup's build_latest_version.sh. The host only needs
# docker and git (awscli is only needed for shared/run-rails-command.sh, not for building) - all
# Ruby/Node toolchain and release-prep work happens inside the build container (see
# shared/build-restructure.sh).
#
# Deliberately does not source toolbox/lib/common.sh / project-config.sh - a build does not need
# AWS account or deploy configuration, only shared/build-vars.sh (the single source of truth for
# BUILD_GIT_BRANCH, REPO_URL, etc).
#
# Usage: build_latest_version.sh [clean] [minor]

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
BUILD_DIR=${TOOLBOX_BUILD_DIR:-${REPO_ROOT}}

if ! command -v docker > /dev/null; then
  echo "docker is required on this host" >&2
  exit 1
fi

cd "${BUILD_DIR}" || exit 1

if [ ! -s shared/build-vars.sh ]; then
  echo "shared/build-vars.sh is not set up - copy shared/build-vars-sample.sh and edit it" >&2
  exit 1
fi
source shared/build-vars.sh

echo "Probing ${BUILD_GIT_BRANCH:-develop} for the target ruby version"
shared/probe-ruby-version.sh "${BUILD_GIT_BRANCH:-develop}"
if [ $? != 0 ]; then
  echo "Failed to probe the ruby version" >&2
  exit 1
fi

echo "Starting build container"
./build.sh "$@"
if [ $? != 0 ]; then
  echo "build.sh failed" >&2
  exit 1
fi

echo "Built version: $(cat shared/build_version.txt)"
