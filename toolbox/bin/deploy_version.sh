#!/bin/bash
# Deploy a specific version to Elastic Beanstalk. Pass APPVER=<tag> or you will be prompted for
# the version to deploy.
#
# This still shells out to env-setup's deploy/aws-eb-deploy.sh (ENV_SETUP_DIR, default
# /var/restructure/env-setup) - see toolbox/bin/deploy_latest_version.sh for why.

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source lib/common.sh
resolve_envtype || exit 1

ENV_SETUP_DIR=${ENV_SETUP_DIR:-/var/restructure/env-setup}
DEPLOYPROFILE="${ENVTYPE}${EBAPPNAME_SUFFIX}-envs.sh"

PCODE="$(bin/get_gpg_secret.sh)"
if [ $? != 0 ] || [ -z "${PCODE}" ]; then
  exit 1
fi

SECRETS_MGR_NAME="${SECRETS_MGR_NAME}" DEPLOYPROFILE="${DEPLOYPROFILE}" SETUPAPP=deploy APPSRC=1 \
  BATCHMODE=true ENVTYPE="${ENVTYPE}" PCODE="${PCODE}" \
  "${ENV_SETUP_DIR}/deploy/aws-eb-deploy.sh"
