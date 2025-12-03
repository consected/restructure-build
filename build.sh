#!/bin/bash
# Build a container if necessary and run the app build

cd -P -- "$(dirname -- "$0")"

echo > shared/build_version.txt

if [ ! -s shared/.netrc ]; then
  echo "shared/.netrc file is not set up. See README.md for more info."
  exit
fi

if [ ! -s shared/build-vars.sh ]; then
  echo "shared/build-vars.sh file is not set up. See README.md for more info."
  exit
fi

if [ ! -s shared/default-ruby-version.sh ]; then
  echo "shared/default-ruby-version.sh file is not set up. See README.md for more info."
  exit
fi

source shared/default-ruby-version.sh

if [ "${RUBY_V}" == "" ]; then
  echo "RUBY_V is not set in shared/default-ruby-version.sh - ensure it is set correctly."
  exit 5
fi

SOURCE_RUBY_V=$(cat output/restructure/.ruby-version)

if [ "${RUBY_V}" != "${SOURCE_RUBY_V}" ]; then
  echo "RUBY_V in shared/default-ruby-version.sh (${RUBY_V}) does not match .ruby-version (${SOURCE_RUBY_V}) - forcing clean"
  forcing_clean='yes'
fi

if [ "$1" == 'clean' ] || [ "${forcing_clean}" == 'yes' ]; then
  echo "sudo is required to clean up the output/restructure* directories"
  sudo docker image rm consected/restructure-build --force
  sudo rm -rf output/restructure*
  sleep 5
fi

if [ -z "$(docker images | grep consected/restructure-build)" ]; then
  docker build . -t consected/restructure-build
fi

if [ -z "$(docker images | grep consected/restructure-build)" ]; then
  echo Container not available
else
  if [ "$1" == 'minor' ] || [ "$2" == 'minor' ]; then
    echo 'Minor version'
    UPVLEVEL=minor
  fi

  docker run --volume="$(pwd)/shared:/shared" --volume="$(pwd)/output:/output" consected/restructure-build /shared/build-restructure.sh ${UPVLEVEL}
fi
