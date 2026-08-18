#!/bin/bash
# Fetch the GPG passcode used to decrypt deploy-time secrets (dev-secrets etc.) from AWS Secrets
# Manager. Requires AWS_REGION, AWS_ACCT and AWS_SMID_SECRETS_PASSCODE to already be set in the
# environment - normally sourced from env_build.sh, which stays project-side in env-setup.

if [ -z "${AWS_SMID_SECRETS_PASSCODE}" ] || [ -z "${AWS_REGION}" ]; then
  echo "AWS_SMID_SECRETS_PASSCODE and AWS_REGION must be set (usually via env_build.sh)" >&2
  exit 1
fi

tmp_secret=$(mktemp)
trap 'rm -f "${tmp_secret}"' EXIT

aws secretsmanager get-secret-value \
  --secret-id "arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCT}:secret:${AWS_SMID_SECRETS_PASSCODE}" \
  --region "${AWS_REGION}" \
  --query 'SecretString' \
  --output text > "${tmp_secret}"

if [ $? != 0 ]; then
  echo "Failed to get the secret" >&2
  exit 1
fi

res=$(cat "${tmp_secret}")
if [ -z "${res}" ]; then
  echo "The secret is empty" >&2
  exit 1
fi

echo "${res}"
