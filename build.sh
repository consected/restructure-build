#!/bin/bash
# Build a container if necessary and run the app build.
#
# Usage:
#   build.sh [clean] [minor]   Build (optionally forcing a clean image rebuild, and/or bumping a
#                              minor version).
#   build.sh image             Clean and rebuild just the image - Ruby/Postgres/Node/etc via
#                              build-container.sh - without running an actual ReStructure build.
#                              Doesn't need shared/build-vars.sh or shared/.netrc. Useful for
#                              producing a dependencies-only image to publish (e.g. to a registry).

cd -P -- "$(dirname -- "$0")" || exit 1

IMAGE_ONLY=
[ "$1" == 'image' ] && IMAGE_ONLY=true

if [ -z "${IMAGE_ONLY}" ]; then
  echo > shared/build_version.txt

  if [ ! -s shared/.netrc ]; then
    echo "shared/.netrc file is not set up. See README.md for more info."
    exit 1
  fi

  if [ ! -s shared/build-vars.sh ]; then
    echo "shared/build-vars.sh file is not set up. See README.md for more info."
    exit 1
  fi
fi

if [ ! -s shared/default-ruby-version.sh ]; then
  echo "shared/default-ruby-version.sh file is not set up. See README.md for more info."
  exit 1
fi

source shared/default-ruby-version.sh

if [ -z "${RUBY_V}" ]; then
  echo "RUBY_V is not set in shared/default-ruby-version.sh - ensure it is set correctly."
  exit 5
fi

if [ -z "${IMAGE_ONLY}" ]; then
  SOURCE_RUBY_V=$(cat output/restructure/.ruby-version 2> /dev/null)

  if [ "${RUBY_V}" != "${SOURCE_RUBY_V}" ]; then
    echo "RUBY_V in shared/default-ruby-version.sh (${RUBY_V}) does not match .ruby-version (${SOURCE_RUBY_V}) - forcing clean"
    forcing_clean='yes'
  fi
fi

if [ "$1" == 'clean' ] || [ "${IMAGE_ONLY}" == 'true' ] || [ "${forcing_clean}" == 'yes' ]; then
  # output/restructure* is owned by root (the container runs as root and writes into the
  # bind-mounted /output), so delete it via a throwaway container instead of "sudo rm" on the
  # host - this only needs docker to be runnable, not host root access.
  # The glob must be expanded by a shell inside the container (via sh -c), not the host shell -
  # /output only exists inside the container, so an unquoted glob here would never match on the
  # host and would be passed through as a literal, non-matching argument instead.
  if [ -n "$(docker images -q consected/restructure-build)" ]; then
    echo "Cleaning output/restructure* via a throwaway container"
    docker run --rm --volume="$(pwd)/output:/output" consected/restructure-build sh -c 'rm -rf /output/restructure*'
  fi
  docker image rm consected/restructure-build --force
  sleep 5
fi

if [ "${IMAGE_ONLY}" == 'true' ]; then
  # Force a fully fresh dependency install rather than possibly reusing old cached layers.
  docker build . --no-cache -t consected/restructure-build
elif [ -z "$(docker images | grep consected/restructure-build)" ]; then
  docker build . -t consected/restructure-build
fi

if [ -z "$(docker images | grep consected/restructure-build)" ]; then
  echo "Container not available"
  exit 1
fi

if [ "${IMAGE_ONLY}" == 'true' ]; then
  # dist/ (not output/) so this tarball isn't swept up by the output/restructure* cleanup glob above.
  mkdir -p dist
  echo "Saving image to dist/restructure-build.tar.gz"
  docker save consected/restructure-build:latest | gzip > dist/restructure-build.tar.gz
  echo "Image consected/restructure-build built and saved to dist/restructure-build.tar.gz ($(du -h dist/restructure-build.tar.gz | cut -f1)) - skipped the ReStructure build."
  exit 0
fi

UPVLEVEL=
if [ "$1" == 'minor' ] || [ "$2" == 'minor' ]; then
  echo 'Minor version'
  UPVLEVEL=minor
fi

docker run --volume="$(pwd)/shared:/shared" --volume="$(pwd)/output:/output" consected/restructure-build /shared/build-restructure.sh "${UPVLEVEL}"
