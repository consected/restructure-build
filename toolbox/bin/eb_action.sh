#!/bin/bash
# Run an arbitrary Elastic Beanstalk setup action (env-setup's aws-eb-deploy.sh SETUPAPP modes:
# deploy, setup, set-dns, etc). Pass the mode as the first argument, or omit it to be prompted.
#
# Usage: eb_action.sh [setup|deploy|set-dns|...]

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source lib/common.sh
resolve_envtype || exit 1

ENV_SETUP_DIR=${ENV_SETUP_DIR:-/var/restructure/env-setup}
DEPLOYPROFILE="${ENVTYPE}${EBAPPNAME_SUFFIX}-envs.sh"

PCODE="$(bin/get_gpg_secret.sh)"
if [ $? != 0 ] || [ -z "${PCODE}" ]; then
  exit 1
fi

SETUPAPP=${1:-prompt}

SECRETS_MGR_NAME="${SECRETS_MGR_NAME}" DEPLOYPROFILE="${DEPLOYPROFILE}" SETUPAPP="${SETUPAPP}" APPSRC=1 \
  APPVER=new-master BATCHMODE=true ENVTYPE="${ENVTYPE}" PCODE="${PCODE}" \
  "${ENV_SETUP_DIR}/deploy/aws-eb-deploy.sh"
