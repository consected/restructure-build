#!/bin/bash
# Determine REPO_URL's .ruby-version without a full host checkout of the app repo, and write it to
# shared/default-ruby-version.sh for the Docker image build to pick up (see Dockerfile / build.sh).
#
# This lets a host that only has docker, git and awscli installed (no rbenv/ruby) drive a build.
#
# Usage: shared/probe-ruby-version.sh [branch]
#   branch defaults to BUILD_GIT_BRANCH from shared/build-vars.sh, or 'develop'.

set -e

cd -P -- "$(dirname -- "$0")/.."

if [ ! -s shared/build-vars.sh ]; then
  echo "shared/build-vars.sh file is not set up. See README.md for more info." >&2
  exit 1
fi

source shared/build-vars.sh

BRANCH=${1:-${BUILD_GIT_BRANCH:-develop}}
PROBE_DIR=$(mktemp -d)
trap 'rm -rf "${PROBE_DIR}"' EXIT

if [ -z "${REPO_URL}" ]; then
  echo "REPO_URL is not set in shared/build-vars.sh" >&2
  exit 1
fi

echo "Probing ${REPO_URL} @ ${BRANCH} for .ruby-version"
# --sparse already limits the clone to root-level files (no subdirectories), which is enough to
# get .ruby-version - no further `sparse-checkout set` is needed (and cone mode would reject a
# file pattern like this one anyway: "'.ruby-version' is not a directory").
git clone --quiet --depth 1 --filter=blob:none --sparse --branch "${BRANCH}" "${REPO_URL}" "${PROBE_DIR}"

RUBY_V=$(cat "${PROBE_DIR}/.ruby-version" 2> /dev/null)
if [ -z "${RUBY_V}" ]; then
  echo "Could not read .ruby-version from ${REPO_URL}@${BRANCH}" >&2
  exit 1
fi

echo "export RUBY_V=${RUBY_V}" > shared/default-ruby-version.sh
echo "Wrote shared/default-ruby-version.sh with RUBY_V=${RUBY_V}"
