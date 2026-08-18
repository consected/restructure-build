# Specify a different ruby version here if the one in .ruby-version should be overridden
# RUBY_V=3.4.2
GIT_EMAIL=youremail
BUILD_GIT_BRANCH=new-master
REPO_URL="https://github.com/yourorg/restructure"
DOCS_REPO_URL="https://github.com/yourorg/restructure-docs"
APPS_REPO_URL="https://github.com/yourorg/restructure-apps"
# For example, to build the consected/restructure repo
# REPO_URL="https://github.com/consected/restructure"
# DOCS_REPO_URL="https://github.com/consected/restructure-docs"
# APPS_REPO_URL="https://github.com/consected/restructure-apps"

# If you want to commit the build to a different repo, uncomment and add it here
# PROD_REPO_URL="https://github.com/prodrepo"
# To prevent pushing results back to the dev repo too, uncomment this
# ONLY_PUSH_TO_PROD_REPO=true
# Only push built assets to the prod repo, cleaning them before
# pushing to the dev repo. Ignored if ONLY_PUSH_TO_PROD_REPO=true
ONLY_PUSH_ASSETS_TO_PROD_REPO=true

# Change to 'true' to run rspec tests
RUN_TESTS=false

DB_NAME=restr_db
TEST_DB_NAME=${DB_NAME}_test
DB_USER=$(whoami)
DB_PASSWORD=root
DB_DEFAULT_SCHEMA=ml_app
APP_DB_SEARCH_PATH=ml_app,ref_data
DUMP_SCHEMAS="ml_app ref_data"
RSPEC_OPTIONS='--exclude-pattern "**/features/**/*_spec.rb"'
# Skip bundle-audit analysis of gems
# SKIP_BUNDLE_AUDIT=true

# --- Container-side release prep (optional) ---
# By default the container builds BUILD_GIT_BRANCH exactly as it finds it (SKIP_RELEASE_PREP=true),
# assuming release prep (upstream sync, dependency updates, CHANGELOG/version reconciliation and the
# merge into BUILD_GIT_BRANCH) was already done, e.g. by app-scripts/release_and_build.sh on the host.
# Set SKIP_RELEASE_PREP=false to have this container perform that prep work itself against FROM_BRANCH.
# SKIP_RELEASE_PREP=false
# FROM_BRANCH=develop
# Set to sync FROM_BRANCH from an upstream fork before building (skipped if unset)
# UPSTREAM_REPO_URL="https://github.com/consected/restructure"
# SKIP_UPSTREAM_SYNC=true
# Skip the 'bundle update' / 'yarn install' dependency refresh step
# SKIP_DEP_UPDATE=true
# Merge BUILD_GIT_BRANCH back into FROM_BRANCH after a build, instead of just copying CHANGELOG.md/version.txt
# MERGE_BACK=true
