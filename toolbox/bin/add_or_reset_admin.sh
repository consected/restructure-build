#!/bin/bash
# Create or reset an admin user on the deployed release. Runs inside the build container - no
# Ruby needed on this host.
#
# Usage: add_or_reset_admin.sh [email]

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source lib/common.sh
resolve_envtype || exit 1

email=$1
if [ -z "${email}" ]; then
  read -r -p "Enter email address for admin user: " email
fi

while [ -z "${reset_secret}" ]; do
  read -r -p "Also reset 2FA secret for this user? (y/n): " reset_secret
  if [ "${reset_secret}" != "y" ] && [ "${reset_secret}" != "n" ]; then
    echo "Please enter 'y' or 'n'."
    reset_secret=""
  fi
done
if [ "${reset_secret}" == "y" ]; then
  export reset_secret=yes
else
  unset reset_secret
fi

docker_run_rails_command add-admin "${email}"

FPHS_SECURE_ADMIN_ENTRY=${FPHS_SECURE_ADMIN_ENTRY:-access-admin}
echo "To log in using the admin details, browse to https://<server-name>?secure_entry=${FPHS_SECURE_ADMIN_ENTRY}"
