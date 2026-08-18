#!/bin/bash
# Container entrypoint for running Rails admin/maintenance commands against a deployed release,
# so the toolbox host needs neither Ruby/Node nor a psql client installed. Invoke via:
#
#   docker run --rm -it \
#     -v "${HOME}/.aws:/root/.aws:ro" \
#     -e AWS_PROFILE -e AWS_ACCT -e AWS_REGION -e SECRETS_MGR_NAME \
#     -e RELEASES_REPO_URL -e APPVER -e DB_NAME -e DB_HOST -e DB_SEARCH_PATH -e FILESTORE_SUBDIR_BASE \
#     consected/restructure-build /shared/run-rails-command.sh <command> [args...]
#
# Commands:
#   migrate                        bundle exec rake db:migrate, as the RDS master (DBA) user
#   add-admin <email>              create/reset an admin user
#   add-filestore-app <id> [dev]   register a filestore app on EFS storage
#   psql                           open an interactive psql session as the RDS master user
#   console                        open a Rails console (production env, app user)
#
# The command always operates on RELEASES_REPO_URL at the APPVER tag/branch - the code that is
# actually deployed - not a development checkout.

export HOME=/root
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
source "$HOME/.bash_profile"
source /shared/rails-functions.sh

COMMAND=$1
shift || true

BUILD_DIR=${BUILD_DIR:-/output/restructure-releases}

function checkout_release() {
  if [ -z "${RELEASES_REPO_URL}" ]; then
    echo "RELEASES_REPO_URL is not set" >&2
    exit 1
  fi
  APPVER=${APPVER:-new-master}

  rm -rf "${BUILD_DIR}"
  echo "Cloning ${RELEASES_REPO_URL}@${APPVER}"
  git clone --branch "${APPVER}" --depth 1 "${RELEASES_REPO_URL}" "${BUILD_DIR}"
  if [ ! -f "${BUILD_DIR}/.git/HEAD" ]; then
    echo "Failed to clone ${RELEASES_REPO_URL}@${APPVER}" >&2
    exit 1
  fi

  cd "${BUILD_DIR}" || exit 1
  local ruby_v
  ruby_v=$(cat .ruby-version)
  if [ "$(rbenv global)" != "${ruby_v}" ]; then
    echo "Installing ruby ${ruby_v} to match the release"
    rbenv install --skip-existing "${ruby_v}"
    rbenv global "${ruby_v}"
  fi
  bundle check || bundle install
}

case "${COMMAND}" in
  migrate)
    checkout_release
    rails_migrate
    ;;
  add-admin)
    checkout_release
    rails_add_admin "$1"
    ;;
  add-filestore-app)
    checkout_release
    rails_add_filestore_app "$1" "$2"
    ;;
  psql)
    set_app_dba_env_vars
    PGPASSWORD=${FPHS_POSTGRESQL_PASSWORD} psql -h "${FPHS_POSTGRESQL_HOSTNAME}" -d "${FPHS_POSTGRESQL_DATABASE}" -U "${FPHS_POSTGRESQL_USERNAME}"
    ;;
  console)
    checkout_release
    set_app_env_vars
    cd "${BUILD_DIR}" || exit 1
    bundle exec rails console
    ;;
  *)
    echo "Usage: run-rails-command.sh <migrate|add-admin|add-filestore-app|psql|console> [args...]" >&2
    exit 1
    ;;
esac
