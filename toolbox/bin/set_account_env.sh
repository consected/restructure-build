#!/bin/bash
# Resolve ENVTYPE from the current AWS account and ensure this host's ~/.aws/config has the
# project's AWS CLI profiles installed. Source this script, or run it directly to check the setup.

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source lib/common.sh
resolve_envtype || exit 1
ensure_aws_profiles

echo "ENVTYPE=${ENVTYPE}"
