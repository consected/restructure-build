#!/bin/bash
# Migrate the deployed release's database. Runs bundle exec rake db:migrate inside the build
# container as the RDS master (DBA) user - no Ruby or psql client needed on this host.

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source lib/common.sh
resolve_envtype || exit 1

docker_run_rails_command migrate
