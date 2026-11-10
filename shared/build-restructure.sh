#!/bin/bash
# Build ReStructure inside the consected/restructure-build container: clone the source repos,
# package gems/yarn assets, migrate and validate against a throwaway Postgres DB, run static
# analysis and (optionally) rspec, then tag and push the release. See README.md for the full
# process description and shared/build-vars-sample.sh for configuration.

source /shared/build-vars.sh

PGSQLBIN=/usr/bin
export PATH=${PGSQLBIN}:$PATH
export PGCLIENTENCODING=UTF8
export HOME=/root
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
source "$HOME/.bash_profile"
source /shared/lib/rbenv.sh
source /shared/lib/git-config.sh
source /shared/lib/repo-setup.sh

BUILD_DIR=/output/restructure
DOCS_BUILD_DIR=${BUILD_DIR}-docs
APPS_BUILD_DIR=${BUILD_DIR}-apps
DEV_COPY=${BUILD_DIR}-dev
PREP_DIR=${BUILD_DIR}-prep
REMOVE_GEMS="e2mmap solargraph"

VERSION_STEP=
[ "$1" == 'minor' ] && VERSION_STEP=minor

# Container-side release prep (see README.md). Defaults to 'true' so existing setups that still
# run app-scripts/release_and_build.sh on the host keep behaving exactly as before. Set to 'false'
# to have this container perform the upstream sync, dependency update, CHANGELOG/version
# reconciliation and develop -> ${BUILD_GIT_BRANCH} merge itself.
SKIP_RELEASE_PREP=${SKIP_RELEASE_PREP:=true}
FROM_BRANCH=${FROM_BRANCH:=develop}
SKIP_UPSTREAM_SYNC=${SKIP_UPSTREAM_SYNC:=false}
SKIP_DEP_UPDATE=${SKIP_DEP_UPDATE:=false}
MERGE_BACK=${MERGE_BACK:=false}

#
# --- Helpers ---
#
# check_version_and_exit, configure_git_for_build, clone_source_repos and checkout_build_branch
# now live in /shared/lib/repo-setup.sh (sourced above) so they can be vendored into
# restructure-test as well.

# Sync FROM_BRANCH from an upstream fork before release prep. Run from within a checkout of REPO_URL.
function sync_upstream() {
  if [ -z "${UPSTREAM_REPO_URL}" ] || [ "${SKIP_UPSTREAM_SYNC}" == 'true' ]; then
    echo "Skipping upstream sync (UPSTREAM_REPO_URL not set or SKIP_UPSTREAM_SYNC=true)"
    return 0
  fi

  echo "Syncing ${FROM_BRANCH} from upstream ${UPSTREAM_REPO_URL}"
  git remote show upstream > /dev/null 2>&1 || git remote add upstream "${UPSTREAM_REPO_URL}"
  git fetch upstream
  git checkout "${FROM_BRANCH}"
  git pull

  if ! git merge upstream/"${FROM_BRANCH}" -X theirs -m "Merge from upstream"; then
    echo "Merge from upstream failed. Will not continue."
    return 100
  fi
  git remote remove upstream
  git push
}

# Update bundled gems and yarn packages on FROM_BRANCH, committing lockfile changes.
function update_dependencies() {
  if [ "${SKIP_DEP_UPDATE}" == 'true' ]; then
    echo "Skipping dependency update (SKIP_DEP_UPDATE=true)"
    return 0
  fi

  echo "Updating gems and yarn packages on ${FROM_BRANCH}"
  local failed=
  bundle update || failed=1
  bin/yarn install || failed=1
  git add -A
  git commit -m "Updated gems and yarn" > /dev/null 2>&1

  if [ "${failed}" ]; then
    echo "Failed to update dependencies"
    return 101
  fi
  git push
}

# Validate/populate CHANGELOG.md, reconcile version.txt with the latest tag, then merge
# FROM_BRANCH into BUILD_GIT_BRANCH. Ported from restructure/app-scripts/release_and_build.sh.
function prepare_release() {
  echo "Checking CHANGELOG.md on ${FROM_BRANCH}"
  local cl_ur
  cl_ur=$(grep '## Unreleased' CHANGELOG.md)
  if [ -z "${cl_ur}" ]; then
    echo "CHANGELOG.md does not have the section '## Unreleased'. Edit and retry."
    return 2
  fi

  if [ -z "${ALLOW_EMPTY_UNRELEASED}" ]; then
    local cl_not_ok
    cl_not_ok=$(grep -Pzl '## Unreleased\n+## ' CHANGELOG.md)
    if [ "${cl_not_ok}" ]; then
      echo "CHANGELOG.md Unreleased section is empty. Populating it from git log"
      local use_prs=''
      [ "${VERSION_STEP}" == 'minor' ] && use_prs='--prs'
      app-scripts/get_changelog_entries_from_git.sh "${BUILD_GIT_BRANCH}" --update-cl ${use_prs}
      git commit CHANGELOG.md -m "Updated CHANGELOG.md with git commits" && git push
    fi

    cl_not_ok=$(grep -Pzl '## Unreleased\n+## ' CHANGELOG.md)
    if [ "${cl_not_ok}" ]; then
      echo "CHANGELOG.md still does not have anything entered for the Unreleased section. Please edit it and retry."
      return 3
    fi
  fi

  echo "Reconciling version.txt with the latest tag"
  local all_tags
  all_tags="$(git tag --sort=-taggerdate)"
  local last_tag
  last_tag=$(echo "${all_tags/-dev/}" | head -n1)
  local curr_ver
  curr_ver=$(cat version.txt)

  if [ "${last_tag}" ] && [ "${curr_ver}" != "${last_tag}" ]; then
    echo "version.txt (${curr_ver}) and latest tag (${last_tag}) do not match. Preferring the tag."
    echo "${last_tag}" > version.txt
    git commit version.txt -m '[Bumped] patch version to latest tag'
    git push
  fi

  if [ "${VERSION_STEP}" == 'minor' ]; then
    curr_ver="$(VERSION_FILE=version.txt app-scripts/upversion.rb -p minor)"
    echo "${curr_ver}" > version.txt
    git commit version.txt -m '[Bumped] minor version'
    git push
  fi

  echo "Merging ${FROM_BRANCH} into ${BUILD_GIT_BRANCH}"
  git checkout "${BUILD_GIT_BRANCH}" || git checkout -b "${BUILD_GIT_BRANCH}" --track origin/"${BUILD_GIT_BRANCH}"
  git pull

  if ! git merge --no-ff -X theirs "${FROM_BRANCH}" -m "Merge ${FROM_BRANCH}"; then
    echo "Failed to merge ${FROM_BRANCH} into ${BUILD_GIT_BRANCH}. Will not continue."
    return 102
  fi
  git push origin --all
}

# Push the built CHANGELOG.md/version.txt (or a full merge) from BUILD_GIT_BRANCH back to FROM_BRANCH.
# Run from within the PREP_DIR checkout used by sync_upstream/prepare_release.
function merge_back() {
  echo "Merging build results back to ${FROM_BRANCH}"
  cd "${PREP_DIR}" || exit 1
  git fetch origin
  git checkout "${FROM_BRANCH}"
  git pull

  if [ "${MERGE_BACK}" == 'true' ]; then
    git merge origin/"${BUILD_GIT_BRANCH}" -m "Merge ${BUILD_GIT_BRANCH} back to ${FROM_BRANCH}"
  else
    git checkout origin/"${BUILD_GIT_BRANCH}" -- CHANGELOG.md version.txt
    git commit -m "Merged release back to ${FROM_BRANCH}" CHANGELOG.md version.txt
  fi
  git push
}

# Run the container-side release prep (sync_upstream, update_dependencies, prepare_release) in a
# disposable clone, pushing results straight to origin. Skipped entirely if SKIP_RELEASE_PREP=true.
function run_release_prep() {
  if [ "${SKIP_RELEASE_PREP}" == 'true' ]; then
    return 0
  fi

  echo "Running container-side release prep on ${FROM_BRANCH}"
  rm -rf "${PREP_DIR}"
  git clone "${REPO_URL}" "${PREP_DIR}" > /dev/null
  cd "${PREP_DIR}" || exit 1
  git config --global user.email "${GIT_EMAIL}"
  git config --global user.name "Restructure Build Process"
  sync_upstream || exit $?
  update_dependencies || exit $?
  prepare_release || exit $?
  cd - > /dev/null || exit 1
}

#
# --- Build steps ---
#

function setup_rails_env() {
  export FPHS_POSTGRESQL_DATABASE=${DB_NAME}
  export FPHS_POSTGRESQL_USERNAME=${DB_USER}
  export FPHS_POSTGRESQL_PASSWORD=${DB_PASSWORD}
  export FPHS_POSTGRESQL_SCHEMA=${APP_DB_SEARCH_PATH}
  export FPHS_POSTGRESQL_PORT=5432
  export FPHS_POSTGRESQL_HOSTNAME=localhost
  FPHS_RAILS_DEVISE_SECRET_KEY="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 128 | head -n 1)"
  export FPHS_RAILS_DEVISE_SECRET_KEY
  SECRET_KEY_BASE="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 128 | head -n 1)"
  export SECRET_KEY_BASE
  export RAILS_ENV=production
}

function start_postgres() {
  if ! command -v rsync > /dev/null; then
    yum install -y rsync
  fi

  if [ ! -d /var/lib/pgsql/data ]; then
    echo "Initializing the database"
    sudo -u postgres "${PGSQLBIN}/initdb" /var/lib/pgsql/data
  fi

  echo "Starting the database"
  sudo -u postgres "${PGSQLBIN}/pg_ctl" start -D /var/lib/pgsql/data -s -o "-p 5432" -w -t 300
  sudo -u postgres psql -c 'SELECT version();'
}

function create_dev_copy() {
  if [ "${ONLY_PUSH_TO_PROD_REPO}" == 'true' ]; then
    return 0
  fi
  echo "Creating a copy of the prod repo for development"
  mkdir -p "${DEV_COPY}"
  rsync -a --delete "${BUILD_DIR}/" "${DEV_COPY}/"
}

# If PROD_REPO_URL is configured, push the build branch there before continuing, replacing origin.
function setup_prod_remote() {
  if [ -z "${PROD_REPO_URL}" ]; then
    return 0
  fi

  echo "Setup remote repos"
  git remote set-url --add origin "${PROD_REPO_URL}"
  git remote set-url --push --add origin "${PROD_REPO_URL}"
  git remote set-url --delete origin "${REPO_URL}"
  git fetch > /dev/null

  git merge origin/"${BUILD_GIT_BRANCH}" -X ours -m "Merge remote" > /dev/null && git commit -a -m "Commit"

  if ! git push --force-with-lease; then
    echo "Failed to push to remotes. Will not continue."
    exit 45
  fi
}

function sync_app_reference_docs() {
  cd "${BUILD_DIR}" || exit 1
  echo "Sync app reference"
  # Remove the link to the docs repo then copy the full structure into the build repo
  # so that it is versioned and can be deployed
  rm -rf docs/app_reference
  mkdir -p docs/app_reference
  rsync -a --delete "${DOCS_BUILD_DIR}/app_reference" docs
  git add docs
}

function sync_apps_source() {
  echo "Setting up org specific ${APPS_BUILD_DIR}/source"
  cd "${APPS_BUILD_DIR}/source" || exit 1

  # Remove symlinks that point back to directories in the -apps repo, then recreate them as real
  # directories, so the org-specific content is versioned directly in the build repo.
  while IFS= read -r -d '' f; do
    [ -L "${BUILD_DIR}/${f}" ] && rm -rf "${BUILD_DIR:?}/${f}"
    mkdir -p "${BUILD_DIR}/${f}"
  done < <(find . -type d -print0)

  # Remove symlinks that point back to files in the -apps repo, then copy them across as real files
  while IFS= read -r -d '' f; do
    rm -f "${BUILD_DIR:?}/${f}"
    cp "${f}" "${BUILD_DIR}/${f}"
  done < <(find . -type f -print0)

  cd "${BUILD_DIR}" || exit 1
  git add .

  echo "Add db"
  rm -f db/app_configs db/app_migrations db/app_specific
  git add db
}

function install_gems_and_yarn() {
  cd "${BUILD_DIR}" || exit 1
  ensure_ruby_version "${RUBY_V}"
  echo "Using ruby version $(rbenv version-name)"
  ruby --version

  echo "Bundle"
  rm -f .bundle/config
  gem install bundler
  git --version

  local gem_name
  for gem_name in ${REMOVE_GEMS}; do
    bundle info "${gem_name}" 2> /dev/null && bundle remove "${gem_name}"
  done

  bundle config set path.system true
  bundle config set cache_all true
  bundle install --no-deployment
  bundle package

  if [ ! -d vendor/cache ]; then
    echo "No vendor/cache after bundle package"
    exit 1
  fi

  if ! bundle check; then
    echo "bundle check failed"
    exit 7
  fi

  git add --force vendor/cache
  git add --force vendor/bundle
  git add Gemfile*
  git add .ruby-version

  bin/yarn install --frozen-lockfile

  if [ ! -d node_modules ]; then
    echo "No node_modules after yarn install"
    exit 1
  fi
  git add --force node_modules
}

function setup_database() {
  if [ -n "$(grep '<<<< HEAD' db/structure 2> /dev/null)" ]; then
    echo 'Merge failures are in the db structure'
    exit 65
  fi

  echo "localhost:5432:*:${DB_USER}:${DB_PASSWORD}" > "${HOME}/.pgpass"
  chmod 600 "${HOME}/.pgpass"

  psql --version

  echo "Create user ${DB_USER} and drop schema in DB ${DB_NAME}"
  sudo -u postgres "${PGSQLBIN}/psql" 2>&1 << EOF
SELECT version();

CREATE USER ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
DROP DATABASE IF EXISTS ${DB_NAME};
CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};
EOF

  echo "Load structure"
  psql -d "${DB_NAME}" -U "${DB_USER}" -h localhost < db/structure.sql > /dev/null

  echo "Grant privileges, setup pgcrypto and replace migration list"
  sudo -u postgres "${PGSQLBIN}/psql" "${DB_NAME}" 2>&1 << EOF
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA ${DB_DEFAULT_SCHEMA} TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA ${DB_DEFAULT_SCHEMA} TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA ${DB_DEFAULT_SCHEMA} TO ${DB_USER};
GRANT ALL PRIVILEGES ON SCHEMA ${DB_DEFAULT_SCHEMA} TO ${DB_USER};

CREATE EXTENSION if not exists pgcrypto;
EOF
}

function upversion_and_update_changelog() {
  echo "Upversion code"
  TARGET_VERSION=$(ruby app-scripts/upversion.rb)

  if [ -z "${TARGET_VERSION}" ]; then
    echo "TARGET_VERSION not set"
    exit 1
  fi

  check_version_and_exit "${VERSION_STEP}"
  echo "Target version ${TARGET_VERSION}"

  echo "Update CHANGELOG"
  local cl_title
  cl_title="## [${TARGET_VERSION}] - $(date +%Y-%m-%d)"
  echo "Changed ## Unreleased -> ${cl_title}"
  sed -i -E "s/## Unreleased/## Unreleased\n\n${cl_title}/" CHANGELOG.md

  git add version.txt CHANGELOG.md
  echo "Commit the new version"
  git commit version.txt CHANGELOG.md -m "new version created $(cat version.txt)"
}

function precompile_assets() {
  echo "Cleanup assets"
  rm -rf public/assets
  RAILS_GROUPS=assets bundle exec rake assets:clobber
  RAILS_GROUPS=assets bundle exec rake assets:precompile --trace

  if [ ! -d public/assets ]; then
    echo "Failed to precompile assets"
    exit 3
  fi

  # Special case to allow third-party CSS in modules to reference images without requiring changes
  # to account for Rails compiling assets with random filenames.
  cp vendor/assets/images/* public/assets/
  git add --force public/assets
}

function run_static_analysis() {
  echo "Run static analysis tests"
  if [ "${SKIP_BRAKEMAN}" != 'true' ]; then
    if bundle exec brakeman -o security/brakeman-output.md; then
      echo "Brakeman OK"
    else
      echo "Brakeman Failed - see: security/brakeman-output.md" >&2
      exit 1
    fi
  fi

  if [ "${SKIP_BUNDLE_AUDIT}" != 'true' ]; then
    bundle exec bundle-audit update > security/bundle-audit-update.md 2>&1

    if bundle exec bundle-audit check > security/bundle-audit-output.md 2>&1; then
      echo "bundle-audit OK"
    else
      echo "bundle-audit Failed ($?) - see: security/bundle-audit-output.md" >&2
      cat security/bundle-audit-output.md
      exit 2
    fi
  fi
}

function dump_schema_and_prepare_test_db() {
  echo "Prep new DB dump"
  rm -f db/dumps/current_schema.sql
  echo "begin;" > /tmp/current_schema.sql

  local -a dump_schema_args=()
  local s
  for s in ${DUMP_SCHEMAS}; do
    dump_schema_args+=(-n "${s}")
  done

  pg_dump -O "${dump_schema_args[@]}" -d "${DB_NAME}" -s -x >> /tmp/current_schema.sql
  echo "commit;" >> /tmp/current_schema.sql
  mv /tmp/current_schema.sql db/dumps/
  bundle exec rails db:schema:dump

  sudo -u postgres "${PGSQLBIN}/psql" "${DB_NAME}" << EOF
drop database if exists ${TEST_DB_NAME};
EOF
}

function run_test_suite() {
  echo "Setting up Zeitwerk check"
  if [ "${RUN_TESTS}" == 'true' ]; then
    app-scripts/drop-test-db.sh > /dev/null
    app-scripts/create-test-db.sh > /dev/null
  else
    app-scripts/drop-test-db.sh 1 > /dev/null
    app-scripts/create-test-db.sh 1 > /dev/null
  fi

  if ! env RAILS_ENV=test bundle exec rails zeitwerk:check; then
    echo "Zeitwerk test failed"
    exit 7
  fi

  if [ "${RUN_TESTS}" == 'true' ]; then
    echo "Run tests"
    FPHS_ADMIN_SETUP=yes RAILS_ENV=test bundle exec rake db:seed

    # RSPEC_OPTIONS (shared/build-vars.sh) is a plain space-separated string, intentionally
    # word-split here; it's not an array to keep that config file simple to hand-edit.
    # shellcheck disable=SC2086,SC2090
    if env RAILS_ENV=test bundle exec rspec ${RSPEC_OPTIONS}; then
      echo "rspec OK"
    else
      echo "rspec Failed"
      exit 1
    fi
  fi
}

function commit_tag_and_push() {
  echo "Pull from: $(git config --get remote.origin.url)"
  git pull

  echo "Add final changes, commit and tag"
  git add -A
  git commit -m "Built and tested release-ready version '${TARGET_VERSION}'"
  git tag -a "${TARGET_VERSION}" -m "Push release"

  echo "Push to: $(git config --get remote.origin.url)"
  git push
  git push origin "${TARGET_VERSION}"
  git push origin --all
}

# Copy the build artifacts (CHANGELOG/version/security reports/schema dump, and optionally built
# assets) into a fresh DEV_COPY repo and push them to REPO_URL, independent of PROD_REPO_URL.
function push_dev_copy() {
  if [ "${ONLY_PUSH_TO_PROD_REPO}" == 'true' ]; then
    return 0
  fi

  echo "Copy files to dev directory for separate git push"
  mkdir -p "${DEV_COPY}/security" "${DEV_COPY}/db/dumps"

  local f
  for f in \
    version.txt CHANGELOG.md \
    Gemfile.lock yarn.lock .ruby-version \
    security/brakeman-output.md \
    security/bundle-audit-update.md \
    security/bundle-audit-output.md \
    db/dumps/current_schema.sql db/structure.sql; do
    cp -a -f "${f}" "${DEV_COPY}/${f}"
  done

  echo "Switching to dev copy ${DEV_COPY}"
  cd "${DEV_COPY}" || exit 1

  rm -rf public/assets node_modules vendor/cache/*

  if [ "${ONLY_PUSH_ASSETS_TO_PROD_REPO}" != 'true' ]; then
    echo "Also pushing assets to dev repo."
    for f in public/assets node_modules vendor/cache/; do
      mkdir -p "${DEV_COPY}/${f}"
      rsync -av "${BUILD_DIR}/${f}/" "${DEV_COPY}/${f}/"
    done
  fi

  echo "Handling git asset, db and security updates"
  git init
  git add -A
  git status

  # DEV_COPY was rsync'd from BUILD_DIR before setup_prod_remote() ran, so its origin already
  # points at REPO_URL - just ensure that explicitly, rather than the previous approach of trying
  # to --delete a PROD_REPO_URL that was never actually set on this checkout (which always failed
  # with "fatal: could not unset" - harmless, but noisy, since there was nothing to delete).
  echo "Pushing changes back to dev repo"
  git remote set-url origin "${REPO_URL}" 2> /dev/null || git remote add origin "${REPO_URL}"
  git remote set-url --push origin "${REPO_URL}"

  echo "Remote set to: $(git config --get remote.origin.url)"
  echo "Final pull from dev repo"
  git fetch origin "${BUILD_GIT_BRANCH}"
  git pull
  git add -A
  git commit -m "Built and tested release-ready version '${TARGET_VERSION}' - dev repo"

  configure_git_for_build
  git merge origin/"${BUILD_GIT_BRANCH}" -m "Merge remote" && git commit -a -m "Commit"

  echo "Final push to dev"
  git push -f
  git tag -a "${TARGET_VERSION}-dev" -m "Push release back to dev"
  git push origin "${TARGET_VERSION}-dev"
  git push origin --all
}

function main() {
  cp /shared/.netrc "${HOME}/.netrc"
  chmod 600 "${HOME}/.netrc"
  echo > /shared/build_version.txt

  setup_rails_env
  start_postgres
  run_release_prep

  clone_source_repos
  checkout_build_branch
  create_dev_copy
  check_version_and_exit "${VERSION_STEP}"
  setup_prod_remote

  sync_app_reference_docs
  sync_apps_source
  install_gems_and_yarn
  setup_database
  upversion_and_update_changelog
  precompile_assets
  run_static_analysis
  dump_schema_and_prepare_test_db
  run_test_suite
  commit_tag_and_push
  push_dev_copy

  if [ "${SKIP_RELEASE_PREP}" != 'true' ]; then
    merge_back
  fi

  echo "${TARGET_VERSION}" > /shared/build_version.txt
}

main "$@"

