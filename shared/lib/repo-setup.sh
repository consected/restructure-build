# shellcheck shell=bash
# Shared repo clone/checkout/version-check helpers, sourced by build-restructure.sh (container
# run time). Depends on shared/lib/rbenv.sh (ensure_ruby_version) and shared/lib/git-config.sh
# (configure_git_for_build) being sourced first.
#
# NOTE: unlike rbenv.sh and git-config.sh, this file is NOT vendored into restructure-test - its
# clone_source_repos/checkout_build_branch/check_version_and_exit assume the ephemeral,
# always-fresh-clone build pipeline (BUILD_GIT_BRANCH, DEV_COPY) and don't fit restructure-test's
# persistent checkout-once-then-pull container model or its simpler (non version-bumping)
# version.txt check. See restructure-test/shared/lib/README.md for details.

# Validate version.txt (in the current directory) is in the expected "major.minor.patch" format
# for the given step ("minor" or "patch"), auto-appending a ".0" patch component once if a bare
# "major.minor" is found for a patch release.
function check_version_and_exit() {
  local step=$1
  local failfast=$2
  local old_ver
  old_ver=$(cat version.txt)
  local -a old_ver_array
  IFS='.' read -r -a old_ver_array < version.txt

  if [ -z "${old_ver_array[0]}" ] || [ -z "${old_ver_array[1]}" ]; then
    echo "Current version is incorrect format for 'minor' update: ${old_ver}"
    echo "This can often be resolved simply by re-running the build script."
    exit 1
  fi

  if [ "${step}" != 'minor' ] && [ -z "${old_ver_array[2]}" ]; then
    echo "Current version is incorrect format for 'patch' update: ${old_ver}"
    if [ "${failfast}" == 'failfast' ]; then
      echo "This can often be resolved simply by re-running the build script."
      exit 1
    fi
    echo "${old_ver}.0" > version.txt
    check_version_and_exit "${step}" failfast
  fi
}

# Clone REPO_URL/DOCS_REPO_URL/APPS_REPO_URL into BUILD_DIR/DOCS_BUILD_DIR/APPS_BUILD_DIR,
# removing any existing checkouts first.
function clone_source_repos() {
  rm -rf "${BUILD_DIR}" "${DOCS_BUILD_DIR}" "${APPS_BUILD_DIR}" "${DEV_COPY}"
  echo "Cloning repo"
  cd "$(dirname "${BUILD_DIR}")" || exit 1
  git clone "${REPO_URL}" "${BUILD_DIR}" > /dev/null
  git clone "${DOCS_REPO_URL}" "${DOCS_BUILD_DIR}" > /dev/null
  git clone "${APPS_REPO_URL}" "${APPS_BUILD_DIR}" > /dev/null

  if [ ! -f "${BUILD_DIR}/.git/HEAD" ]; then
    echo "Failed to get the build repo"
    exit 1
  fi
  if [ ! -f "${DOCS_BUILD_DIR}/.git/HEAD" ]; then
    echo "Failed to get the docs repo"
    exit 8
  fi
  if [ ! -f "${APPS_BUILD_DIR}/.git/HEAD" ]; then
    echo "Failed to get the apps repo"
    exit 8
  fi
}

# Check out BUILD_GIT_BRANCH in BUILD_DIR, ensuring the required Ruby version and git identity
# are set first.
function checkout_build_branch() {
  cd "${BUILD_DIR}" || exit 1

  if [ -z "${RUBY_V}" ]; then
    RUBY_V="$(cat "${BUILD_DIR}/.ruby-version")"
    echo "RUBY_V is not set. Using value in source ${BUILD_DIR}/.ruby-version = ${RUBY_V}"
  fi
  ensure_ruby_version "${RUBY_V}"
  git stash save

  configure_git_for_build

  echo "Checking out ${BUILD_GIT_BRANCH}"
  git checkout "${BUILD_GIT_BRANCH}" || git checkout -b "${BUILD_GIT_BRANCH}" --track origin/"${BUILD_GIT_BRANCH}"
  git pull
  mkdir -p tmp && chmod 774 tmp
  mkdir -p log && chmod 774 log
  touch log/delayed_job.log
  chmod 664 log/delayed_job.log

  if [ ! -f Gemfile ]; then
    echo "No Gemfile found after checking out branch ${BUILD_GIT_BRANCH} to $(pwd)"
    exit 1
  fi
}
