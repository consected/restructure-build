#!/bin/bash
# Setup the build container with
#    docker build . --no-cache -t consected/restructure-build

# set -xv
source /shared/build-vars.sh
export HOME=/root

PGVER=15

yum update -y
yum install -y deltarpm sudo rsync adduser
yum update -y

curl --silent --location https://dl.yarnpkg.com/rpm/yarn.repo | tee /etc/yum.repos.d/yarn.repo
yum install https://rpm.nodesource.com/pub_16.x/nodistro/repo/nodesource-release-nodistro-1.noarch.rpm -y
yum install nodejs -y --setopt=nodesource-nodejs.module_hotfixes=1

yum install -y git yarn \
  openssl-devel readline-devel zlib-devel \
  gcc gcc-c++ make which mlocate \
  libffi libffi-devel libyaml libyaml-devel rsync sudo \
  tar bzip2 \
  words unzip

if [ $? != 0 ]; then
  echo 'Failed to install main packages'
  exit 7
fi

yum clean metadata

yum install -y postgresql${PGVER} postgresql${PGVER}-server libpq-devel postgresql${PGVER}-contrib

if [ -z "$(which psql)" ]; then
  echo "Failed to install psql"
  exit 8
fi

adduser postgres
ls /usr/
ls /usr/bin/
# Setup Postgres
sudo -u postgres initdb /var/lib/pgsql/data
sudo -u postgres pg_ctl start -D /var/lib/pgsql/data -s -o "-p 5432" -w -t 300
psql --version
sudo -u postgres psql -c 'SELECT version();' 2>&1

# For UI features testing
# yum install -y firefox Xvfb x11vnc

# Install rbenv
git clone https://github.com/rbenv/rbenv.git ${HOME}/.rbenv
cd ${HOME}/.rbenv && src/configure && make -C src
echo 'eval "$(rbenv init -)"' >> ${HOME}/.bash_profile
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
eval "$(rbenv init -)"
. /root/.bash_profile
curl -fsSL https://github.com/rbenv/rbenv-installer/raw/master/bin/rbenv-doctor | bash
mkdir -p "$(rbenv root)"/plugins
git clone https://github.com/rbenv/ruby-build.git "$(rbenv root)"/plugins/ruby-build
rbenv install --list
rbenv rehash

# Install ruby, etc
if [ "$(rbenv local)" != "${RUBY_V}" ]; then
  rbenv install ${RUBY_V}
  rbenv global ${RUBY_V}
  gem install bundler
fi
