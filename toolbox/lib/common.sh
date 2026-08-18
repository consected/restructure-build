#!/bin/bash
# Shared helpers for toolbox/bin/*.sh, sourced by every script in that directory.
#
# This deliberately does not depend on env-setup's /root/setup/common_functions.sh -
# the toolbox scripts here are meant to be self-contained and project-agnostic.

TOOLBOX_LIB_DIR=$(dirname "${BASH_SOURCE[0]}")
TOOLBOX_ROOT=$(cd "${TOOLBOX_LIB_DIR}/.." && pwd)

# Load project-config.sh, searching (in order): $PROJECT_CONFIG (explicit override),
# /var/restructure/toolbox-config.sh (deployed override), then the sample-adjacent
# toolbox/config/project-config.sh (for a local/dev checkout).
function load_project_config() {
  local candidate
  for candidate in \
    "${PROJECT_CONFIG}" \
    /var/restructure/toolbox-config.sh \
    "${TOOLBOX_ROOT}/config/project-config.sh"; do

    if [ -n "${candidate}" ] && [ -f "${candidate}" ]; then
      source "${candidate}"
      echo "Loaded project config from ${candidate}" >&2
      return 0
    fi
  done

  echo "No project-config.sh found. Copy toolbox/config/project-config.sample.sh and fill it in," \
    "then set PROJECT_CONFIG=/path/to/project-config.sh or place it at /var/restructure/toolbox-config.sh" >&2
  return 1
}

load_project_config || exit 1

# Resolve ENVTYPE (e.g. dev/prod) from AWS_ACCT using the AWS_ACCOUNT_ENVTYPES map in
# project-config.sh. Exits with an error if the account is not recognized.
function resolve_envtype() {
  if [ -z "${AWS_ACCT}" ]; then
    echo "AWS_ACCT is not set" >&2
    return 1
  fi

  ENVTYPE=${AWS_ACCOUNT_ENVTYPES[${AWS_ACCT}]}
  if [ -z "${ENVTYPE}" ]; then
    echo "AWS account ${AWS_ACCT} is not in AWS_ACCOUNT_ENVTYPES (project-config.sh). Will not continue." >&2
    return 1
  fi
  export ENVTYPE
}

# Append the toolbox's AWS CLI profiles to ~/.aws/config if they are not already present.
# AWS_PROFILES_FILE defaults to toolbox/config/aws-profiles.sample; override with a filled-in copy.
function ensure_aws_profiles() {
  local profiles_file=${AWS_PROFILES_FILE:-${TOOLBOX_ROOT}/config/aws-profiles.sample}
  mkdir -p "${HOME}/.aws"
  touch "${HOME}/.aws/config"

  if [ -f "${profiles_file}" ] && ! grep -q "$(head -n1 "${profiles_file}")" "${HOME}/.aws/config"; then
    cat "${profiles_file}" >> "${HOME}/.aws/config"
  fi
}

# Run shared/run-rails-command.sh in the build container. Requires docker and the toolbox's
# restructure-build checkout (TOOLBOX_BUILD_DIR, default /var/restructure/restructure-build).
# Usage: docker_run_rails_command migrate|add-admin|add-filestore-app|psql|console [args...]
function docker_run_rails_command() {
  local build_dir=${TOOLBOX_BUILD_DIR:-/var/restructure/restructure-build}
  local tty_flag='-i'
  [ -t 0 ] && tty_flag='-it'

  docker run --rm ${tty_flag} \
    --network host \
    -v "${HOME}/.aws:/root/.aws:ro" \
    -e AWS_PROFILE -e AWS_ACCT -e AWS_REGION -e SECRETS_MGR_NAME \
    -e RELEASES_REPO_URL -e APPVER -e DB_NAME -e DB_HOST -e DB_SEARCH_PATH -e FILESTORE_SUBDIR_BASE \
    -e reset_secret \
    -v "${build_dir}/shared:/shared" \
    consected/restructure-build /shared/run-rails-command.sh "$@"
}
