#!/bin/bash
# Bootstrap a toolbox host: set up git credentials, then clone only restructure-build (this
# repo) and env-setup - the app source repos (restructure, -apps, -docs) are only ever cloned
# inside the build container now (see shared/build-restructure.sh), so they no longer need a
# host checkout.
#
# Usage: setup_source.sh [reset]   ('reset' forces re-entry of git credentials)

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "${SCRIPT_DIR}" || exit 1
ADMIN_GRP=${ADMIN_GRP:-wheel}
RE_ROOT=${RE_ROOT:-/var/restructure}
GIT_CRED="${HOME}/.git-credentials"
NETRC="${HOME}/.netrc"

source /etc/profile
source ~/.bash_profile

# project-config.sh may not exist yet on a brand new host - load it if present, but don't fail.
[ -f "${SCRIPT_DIR}/../config/project-config.sh" ] && source "${SCRIPT_DIR}/../config/project-config.sh"

function get_config() {
  local config_file="${HOME}/config/$1"
  if [ -s "${config_file}" ]; then
    export "$1=$(cat "${config_file}")"
  else
    return 1
  fi
}

function save_config() {
  local val=$2
  local config_file="${HOME}/config/$1"
  mkdir -p "${HOME}/config"
  echo "${val}" > "${config_file}"
  export "$1=${val}"
}

get_config GIT_EMAIL
get_config GIT_FIRSTNAME
get_config GIT_LASTNAME
get_config GH_BASEURL

if [ "${GIT_EMAIL}" ] && [ "${GIT_FIRSTNAME}" ] && [ "${GIT_LASTNAME}" ] && [ "${GH_BASEURL}" ] && [ "$1" != 'reset' ]; then
  git config --global user.email "${GIT_EMAIL}"
  git config --global user.name "${GIT_FIRSTNAME} ${GIT_LASTNAME}"
  git config --replace-all --global credential.helper store
else
  echo 'Enter the following information for Git'
  read -r -p 'Email address: ' email
  read -r -p 'First name: ' firstname
  read -r -p 'Last name: ' lastname
  read -r -p 'Github username: ' ghusername
  read -r -p 'Github access key: ' ghaccesskey
  ghbaseurl="${REPO_BASE_URL}"
  [ -z "${ghbaseurl}" ] && read -r -p "Github base URL (for example https://github.com/yourorg): " ghbaseurl

  save_config GIT_EMAIL "${email}"
  save_config GIT_FIRSTNAME "${firstname}"
  save_config GIT_LASTNAME "${lastname}"
  save_config GH_BASEURL "${ghbaseurl}"

  git config --global user.email "${GIT_EMAIL}"
  git config --global user.name "${GIT_FIRSTNAME} ${GIT_LASTNAME}"
  git config --replace-all --global credential.helper store

  echo "https://${ghusername}:${ghaccesskey}@${GH_BASEURL/https:\/\//}" > "${GIT_CRED}"
  echo "machine github.com login ${ghusername} password ${ghaccesskey}" > "${NETRC}"
  chmod 600 "${NETRC}"
  chmod 600 "${GIT_CRED}"
fi

sudo mkdir -p "${RE_ROOT}"
sudo chgrp "${ADMIN_GRP}" "${RE_ROOT}"
sudo chmod o+rwx,g+rwx "${RE_ROOT}"

cd "${RE_ROOT}" || exit 1

for r in "${BUILD_REPO_NAME:-restructure-build}" "${ENV_SETUP_REPO_NAME:-env-setup}"; do
  sudo rm -rf "${r}"
  git clone "${GH_BASEURL}/${r}.git"
  sudo chgrp --recursive "${ADMIN_GRP}" "${r}"
done

cp -f "${NETRC}" "${BUILD_REPO_NAME:-restructure-build}/shared/.netrc"

echo "Toolbox source set up in ${RE_ROOT}."
echo "Next: copy ${BUILD_REPO_NAME:-restructure-build}/toolbox/config/project-config.sample.sh to"
echo "project-config.sh (or ${RE_ROOT}/toolbox-config.sh) and fill it in."
