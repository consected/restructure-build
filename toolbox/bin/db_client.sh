#!/bin/bash
# Open an interactive psql session as the RDS master user, via the build container - no psql
# client needed on this host. The master password is resolved from AWS Secrets Manager inside
# the container (SECRETS_MGR_NAME, from project-config.sh).

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source lib/common.sh
resolve_envtype || exit 1

echo "***************************************************************"
echo "Logging in as the RDS Master User. Be very careful."
echo "***************************************************************"

docker_run_rails_command psql
