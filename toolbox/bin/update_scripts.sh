#!/bin/bash
# Update/install the toolbox scripts on this host. Supports two delivery modes:
#   git   - clone/pull TOOLBOX_REPO_URL (this repo) and install toolbox/bin/*.sh into RE_ROOT
#   s3    - fall back to env-setup's existing S3 template sync mechanism, unchanged
#
# Usage: update_scripts.sh [git|s3]
# The chosen mode is persisted to RE_ROOT/.toolbox-delivery-mode for future runs.

if [ "$(whoami)" != 'root' ]; then
  echo "Must run as root! Re-run with sudo $0" >&2
  exit 1
fi

RE_ROOT=${RE_ROOT:-/var/restructure}
MODE_FILE="${RE_ROOT}/.toolbox-delivery-mode"
[ -f "${RE_ROOT}/toolbox-config.sh" ] && source "${RE_ROOT}/toolbox-config.sh"

MODE=$1
[ -z "${MODE}" ] && [ -f "${MODE_FILE}" ] && MODE=$(cat "${MODE_FILE}")
[ -z "${MODE}" ] && [ -n "${TOOLBOX_REPO_URL}" ] && MODE=git
[ -z "${MODE}" ] && MODE=s3

function update_via_git() {
  local branch=${TOOLBOX_REPO_BRANCH:-master}
  local build_dir="${RE_ROOT}/restructure-build"

  if [ -z "${TOOLBOX_REPO_URL}" ]; then
    echo "TOOLBOX_REPO_URL is not set (RE_ROOT/toolbox-config.sh or project-config.sh)" >&2
    return 1
  fi

  if [ -d "${build_dir}/.git" ]; then
    git -C "${build_dir}" fetch origin "${branch}"
    git -C "${build_dir}" checkout "${branch}"
    git -C "${build_dir}" pull
  else
    rm -rf "${build_dir}"
    git clone --branch "${branch}" "${TOOLBOX_REPO_URL}" "${build_dir}"
  fi

  install -m 0755 "${build_dir}"/toolbox/bin/*.sh "${RE_ROOT}/"
}

function update_via_s3() {
  source /etc/profile
  NOLOCK=t . /root/setup/common_functions.sh
  get_source run_toolbox_actions.sh
}

case "${MODE}" in
  git)
    update_via_git || exit 1
    ;;
  s3)
    update_via_s3
    ;;
  *)
    echo "Unknown mode '${MODE}' - expected 'git' or 's3'" >&2
    exit 1
    ;;
esac

echo "${MODE}" > "${MODE_FILE}"
echo "Toolbox scripts updated via '${MODE}' mode."
