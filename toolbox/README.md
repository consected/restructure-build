# Toolbox: project-agnostic build/deploy scripts

This directory generalizes the toolbox host scripts that were previously only available as
project-specific templates in a downstream `env-setup` repo. The goal is that a toolbox host only
needs `docker`, `git` and `awscli` installed - all Ruby/Node toolchain work, release preparation,
and Rails admin/migration commands run inside the `consected/restructure-build` container (see
`../shared/build-restructure.sh`, `../shared/rails-functions.sh` and `../shared/run-rails-command.sh`).

## Layout

- `bin/` - the CLI scripts an operator runs on the toolbox host
- `lib/common.sh` - shared helpers: project-config loading, AWS profile setup, the
  `docker_run_rails_command` wrapper
- `config/project-config.sample.sh` - all the project-specific variables these scripts need
- `config/aws-profiles.sample` - sample AWS CLI profile block

## Script reference (`toolbox/bin/`)

| Script | Purpose |
| --- | --- |
| `setup_source.sh` | Bootstrap a toolbox host: git credentials, clone this repo + `env-setup` |
| `set_account_env.sh` | Resolve `ENVTYPE` from the current AWS account, install AWS CLI profiles |
| `build_latest_version.sh` | Build the latest version - see the main [README](../README.md) |
| `migrate_db.sh` | Run `db:migrate` against the deployed release, in the container |
| `add_or_reset_admin.sh` | Create/reset an admin user, in the container |
| `add_filestore_app.sh` | Register a filestore app on EFS storage, in the container |
| `db_client.sh` | Open an interactive `psql` session as the RDS master user, in the container |
| `get_gpg_secret.sh` | Fetch the GPG passcode for deploy-time secrets from AWS Secrets Manager (used by the `deploy_*.sh`/`eb_action.sh` scripts below, not usually run directly) |
| `deploy_latest_version.sh` | Deploy `new-master` to Elastic Beanstalk (see "What's deferred") |
| `deploy_version.sh` | Deploy a specific tag to Elastic Beanstalk (see "What's deferred") |
| `eb_action.sh` | Run an arbitrary EB setup action (`setup`/`deploy`/`set-dns`/...) (see "What's deferred") |
| `update_scripts.sh` | Update the toolbox scripts on this host (see "Toolbox delivery" below) |

## New project onboarding

1. Provision a toolbox host with `docker`, `git` and `awscli` installed.
2. Run `toolbox/bin/setup_source.sh` to set up git credentials and clone this repo plus your
   `env-setup` repo into `/var/restructure` (override with `RE_ROOT`).
3. Copy `toolbox/config/project-config.sample.sh` to `project-config.sh` (or
   `/var/restructure/toolbox-config.sh`) and fill in your project's values.
4. Copy `../shared/build-vars-sample.sh` to `../shared/build-vars.sh` and fill it in (see the main
   [README](../README.md)).
5. Create `env-setup/aws-setup/envs/<profile>-envs.sh` files and `env-setup/deploy/aws/<account>/`
   as before - this migration does not change that side of things yet (see "What's deferred"
   below).
6. Run `toolbox/bin/build_latest_version.sh` to build, and `toolbox/bin/migrate_db.sh` /
   `add_or_reset_admin.sh` / `add_filestore_app.sh` / `db_client.sh` for the containerized Rails
   admin commands.

## What's deferred

Elastic Beanstalk deployment (`deploy_latest_version.sh`, `deploy_version.sh`, `eb_action.sh`) is
still implemented by shelling out to `env-setup/deploy/aws-eb-deploy.sh` (see `ENV_SETUP_DIR` in
those scripts). That script is several hundred lines of AWS EB console workflow logic
(profile/key setup, environment selection, `eb`/`awscli` bootstrapping, S3 asset bucket wiring)
that has not been ported into this repo. Porting it blind, without a way to test it against real
EB infrastructure, is too risky to include in this generalization pass - it should be done as a
separate, carefully-tested follow-up once this repo's copy can be exercised against a real
deployment.

Similarly, AWS infrastructure setup (VPC/RDS/EFS/IAM), EB `.ebextensions`/platform hooks, and the
toolbox host's own provisioning (`setup_toolbox.sh`, `build_toolbox.sh`,
`/root/setup/common_functions.sh`) all stay project-side in `env-setup`, unchanged.

## Toolbox delivery

`bin/update_scripts.sh` supports two ways to get `toolbox/bin/*.sh` onto a host:

- `git` mode: set `TOOLBOX_REPO_URL` (and optionally `TOOLBOX_REPO_BRANCH`) in
  `project-config.sh` or `/var/restructure/toolbox-config.sh`; the script clones/pulls this repo
  and installs `toolbox/bin/*.sh` into `/var/restructure/`.
- `s3` mode (default when `TOOLBOX_REPO_URL` is unset): falls back to env-setup's existing S3
  template sync (`run_toolbox_actions.sh`), unchanged.

Force a mode with `update_scripts.sh git` or `update_scripts.sh s3`; the choice is remembered in
`/var/restructure/.toolbox-delivery-mode`.
