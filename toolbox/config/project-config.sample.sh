#!/bin/bash
# Sample project-config.sh for the generalized restructure-build toolbox.
#
# Copy this file to project-config.sh (in the same directory, or anywhere on the toolbox host)
# and fill in your project's values. toolbox/lib/common.sh sources it automatically - see that
# file for the search order. Never commit a filled-in copy; it may contain account IDs and
# internal naming that you may not want public, even though it holds no secrets itself.

# --- Git repositories ---
REPO_BASE_URL="https://github.com/yourorg"
REPO_NAME=restructure
BUILD_REPO_NAME=restructure-build
APPS_REPO_NAME=restructure-apps
DOCS_REPO_NAME=restructure-docs
ENV_SETUP_REPO_NAME=env-setup
RELEASES_REPO_NAME=restructure-releases

# Set to sync FROM_BRANCH from an upstream fork before building. Leave unset to skip.
# UPSTREAM_REPO_URL="https://github.com/consected/restructure"

# Only needed if built code is pushed to a separate production repo
# PROD_REPO_URL="https://github.com/yourorg/restructure-releases"

# --- Branches / versions ---
BUILD_GIT_BRANCH=new-master
FROM_BRANCH=develop
# Version/tag of RELEASES_REPO_NAME to deploy or run Rails commands against
APPVER=new-master

# --- AWS accounts ---
# Map AWS account IDs to a short environment type name, used to pick the right
# aws-setup/envs/<ENVTYPE><EBAPPNAME_SUFFIX>-envs.sh deployment profile.
declare -A AWS_ACCOUNT_ENVTYPES=(
  [123456789012]=dev
  [210987654321]=prod
)
EBAPPNAME_SUFFIX=myapp
# DEPLOYPROFILE pattern: ${ENVTYPE}${EBAPPNAME_SUFFIX}-envs.sh (resolved by toolbox/bin scripts)

SECRETS_MGR_NAME="MyApp/PROD/ReStructure/Secrets"
EBAPPNAME=restructure-demo
ACCOUNT_NAME=myaccount

# --- Database ---
DB_NAME=restr
DB_DEFAULT_SCHEMA=ml_app
APP_DB_SEARCH_PATH=ml_app,ref_data
DUMP_SCHEMAS="ml_app ref_data"
# EFS mount subdirectory base name used by add_filestore_app.sh (see shared/rails-functions.sh)
FILESTORE_SUBDIR_BASE=app

# --- Test / build behaviour ---
RUN_TESTS=false
RSPEC_OPTIONS='--exclude-pattern "**/features/**/*_spec.rb"'
# SKIP_BUNDLE_AUDIT=true
# SKIP_BRAKEMAN=true
# SKIP_UPSTREAM_SYNC=true
# SKIP_DEP_UPDATE=true
# SKIP_RELEASE_PREP=true
# MERGE_BACK=true

# --- Toolbox delivery (see toolbox/bin/update_scripts.sh) ---
# Set to have update_scripts.sh install the toolbox from a git clone instead of the S3 template
# sync. Leave unset to keep using the S3 delivery mechanism.
# TOOLBOX_REPO_URL="https://github.com/yourorg/restructure-build"
# TOOLBOX_REPO_BRANCH=master
