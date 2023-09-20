RUBY_V=3.0.6
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
