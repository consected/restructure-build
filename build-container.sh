#!/bin/bash
# Set up the build container image at Docker build time (invoked by the Dockerfile's RUN step -
# not run directly). To rebuild from scratch: docker build . --no-cache -t consected/restructure-build

# set -xv
source /shared/default-ruby-version.sh
source /shared/lib/rbenv.sh
export HOME=/root

if [ -z "${RUBY_V}" ]; then
  echo "RUBY_V is not set in default-ruby-version.sh - ensure the Dockerfile copies it correctly" >&2
  exit 5
fi

PGVER=15
NODEJS_VERSION=26

function install_packages() {
  yum update -y
  yum install -y deltarpm sudo rsync adduser
  yum update -y

  curl --silent --location https://dl.yarnpkg.com/rpm/yarn.repo | tee /etc/yum.repos.d/yarn.repo
  curl -fsSL "https://rpm.nodesource.com/setup_${NODEJS_VERSION}.x" -o nodesource_setup.sh
  bash nodesource_setup.sh
  yum install -y nodejs
  node -v

  if ! yum install -y git yarn \
    openssl-devel readline-devel zlib-devel \
    gcc gcc-c++ make which mlocate \
    libffi libffi-devel libyaml libyaml-devel rsync sudo \
    tar bzip2 \
    words unzip; then
    echo 'Failed to install main packages' >&2
    exit 7
  fi

  yum clean metadata
  yum install -y "postgresql${PGVER}" "postgresql${PGVER}-server" libpq-devel "postgresql${PGVER}-contrib"

  if ! command -v psql > /dev/null; then
    echo "Failed to install psql" >&2
    exit 8
  fi
}

function init_postgres() {
  adduser postgres
  sudo -u postgres initdb /var/lib/pgsql/data
  sudo -u postgres pg_ctl start -D /var/lib/pgsql/data -s -o "-p 5432" -w -t 300
  psql --version
  sudo -u postgres psql -c 'SELECT version();' 2>&1
}

# For UI features testing, also install: firefox Xvfb x11vnc

install_packages
init_postgres
install_rbenv
ensure_ruby_version "${RUBY_V}"
gem install bundler

