#!/bin/bash
# Register a filestore app for the deployed release. Runs inside the build container - no Ruby
# needed on this host. The EFS/NFS filestore mount itself is still host/infra managed (out of
# scope for this toolbox); extend docker_run_rails_command in lib/common.sh with a bind mount for
# FILESTORE_NFS_DIR if the app-scripts/setup_filestore_app.sh task needs to see it directly.

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source lib/common.sh
resolve_envtype || exit 1

app_id=$1
while [ -z "${app_id}" ]; do
  read -r -p 'Enter app id: ' app_id
done

while [ "${dev_server}" != y ] && [ "${dev_server}" != n ]; do
  read -r -p 'Is this a development server? (y/n) ' dev_server
done
[ "${dev_server}" == 'n' ] && dev_server=''

docker_run_rails_command add-filestore-app "${app_id}" "${dev_server}"
