#!/bin/bash
# Rails runtime environment helpers for running admin/maintenance commands against a deployed
# release, containerized from env-setup/server-build/scripts/setup_rails.sh's equivalent
# functions. Unlike that source, these do not depend on that host's common_functions.sh /
# log_function machinery - they are meant to be sourced by shared/run-rails-command.sh only.
#
# Secrets are always resolved from AWS Secrets Manager inside the container (mounted ~/.aws
# credentials), never passed as command-line arguments.

# Fetch app secrets from AWS Secrets Manager and export the Rails env vars needed to run rake
# tasks / app-scripts against the deployed app, as the standard app DB user.
function set_app_env_vars() {
  if [ -z "${SECRETS_MGR_NAME}" ]; then
    echo "SECRETS_MGR_NAME is not set" >&2
    return 1
  fi
  if [ -z "${AWS_ACCT}" ] || [ -z "${AWS_REGION}" ]; then
    echo "AWS_ACCT and AWS_REGION must be set" >&2
    return 1
  fi

  local tmp_secrets
  tmp_secrets=$(mktemp)
  aws secretsmanager get-secret-value \
    --secret-id "arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCT}:secret:${SECRETS_MGR_NAME}" \
    --region "${AWS_REGION}" --output text --query 'SecretString' \
    > "${tmp_secrets}"

  if [ $? != 0 ] || [ ! -s "${tmp_secrets}" ]; then
    echo "Failed to retrieve secrets from AWS Secrets Manager (${SECRETS_MGR_NAME})" >&2
    rm -f "${tmp_secrets}"
    return 1
  fi

  source "${tmp_secrets}"
  rm -f "${tmp_secrets}"

  export FPHS_2FA_AUTH_DISABLED=user
  export FPHS_POSTGRESQL_DATABASE=${DB_NAME}
  export FPHS_POSTGRESQL_USERNAME=${DB_USERNAME}
  export FPHS_POSTGRESQL_PASSWORD=${DB_PASSWORD}
  export FPHS_POSTGRESQL_SCHEMA=${DB_SEARCH_PATH}
  export FPHS_POSTGRESQL_PORT=5432
  export FPHS_POSTGRESQL_HOSTNAME=${DB_HOST}
  export RAILS_ENV=production
  export FILESTORE_CONTAINERS_DIRNAME=containers
  export FILESTORE_NFS_DIR=${FILESTORE_NFS_DIR:-/mnt/fphsfs}
  export FILESTORE_TEMP_UPLOADS_DIR=/tmp/uploads
  export FPHS_X_SENDFILE_HEADER="X-Accel-Redirect"
  export FPHS_ENC_SECRET_KEY_BASE="${FPHS_ENC_SECRET_KEY_BASE}"
  export FPHS_ENC_SALT="${FPHS_ENC_SALT}"
  export FPHS_RAILS_DEVISE_SECRET_KEY="${FPHS_RAILS_DEVISE_SECRET_KEY}"
}

# Same as set_app_env_vars, but swaps in the RDS master (DBA) credentials so migrations can run.
function set_app_dba_env_vars() {
  set_app_env_vars || return 1
  export FPHS_POSTGRESQL_USERNAME=${DBA_USER}
  export FPHS_POSTGRESQL_PASSWORD=${RDS_MASTER_PW}
}

function rails_migrate() {
  set_app_dba_env_vars || return 1
  cd "${BUILD_DIR}" || return 1
  bundle exec rake db:migrate
}

function rails_add_admin() {
  local email=$1
  if [ -z "${email}" ]; then
    echo "rails_add_admin requires an email address" >&2
    return 1
  fi
  set_app_env_vars || return 1
  cd "${BUILD_DIR}" || return 1
  app-scripts/add_admin.sh "${email}"
}

# Register a filestore app. Call with app_id and optionally a second non-blank argument if this
# is a dev server. FILESTORE_SUBDIR_BASE (from project-config.sh) names the EFS mount subdirectory.
function rails_add_filestore_app() {
  local app_id=$1
  local is_dev=$2

  if [ -z "${app_id}" ]; then
    echo "rails_add_filestore_app requires an app id" >&2
    return 1
  fi

  local dev_suffix=''
  [ "${is_dev}" ] && dev_suffix='dev'

  set_app_env_vars || return 1
  cd "${BUILD_DIR}" || return 1
  SUBDIR="${FILESTORE_SUBDIR_BASE:-app}${dev_suffix}-main" RAILS_ENV=production app-scripts/setup_filestore_app.sh "${app_id}"
}
