# Build ReStructure

A Dockerfile and scripts to build [ReStructure](https://github.com/consected/restructure) and
commit it to a repository. Deployable code is made available, and the latest version
(in the source `version.txt`) will be upversioned.

## ⚠️ This pushes real commits and tags

Running a build **clones, tags, commits and pushes** to whatever `REPO_URL`/`PROD_REPO_URL` you
configure in `shared/build-vars.sh` - there is no dry-run mode. Point those at throwaway/test
repos while you're getting familiar with this tool, not at a real production repo, unless you
mean to cut an actual release.

## Quick start

A fresh host only needs `docker` and `git` installed (`awscli` is only needed later, for
`shared/run-rails-command.sh` - not for building).

1. **Get this repo**:

       git clone https://github.com/consected/restructure-build
       cd restructure-build

2. **Configure the build** - see [Configuration](#configuration) for the full variable reference:

       cp shared/build-vars-sample.sh shared/build-vars.sh
       # edit shared/build-vars.sh - set at least REPO_URL, DOCS_REPO_URL, APPS_REPO_URL,
       # GIT_EMAIL and the DB_* values

3. **Set up git credentials** the container will use to clone/push:

       cp ~/.netrc shared/.netrc   # or create it - see "Configuration"
       chmod 600 shared/.netrc

4. **Build**:

       toolbox/bin/build_latest_version.sh

   The first run also builds the `consected/restructure-build` Docker image (slow - see
   [The Docker image](#the-docker-image)). This is equivalent to running `./build.sh` directly;
   `build_latest_version.sh` only adds config sanity checks and a `shared/probe-ruby-version.sh`
   step first (updates `shared/default-ruby-version.sh` to match the target branch's
   `.ruby-version` - optional, since a version is already checked into this repo).

   To also merge upstream changes into `FROM_BRANCH` before building (rather than assuming that
   already happened elsewhere), set in `shared/build-vars.sh`:

       SKIP_RELEASE_PREP=false
       FROM_BRANCH=develop
       UPSTREAM_REPO_URL="https://github.com/consected/restructure"

   See [Container-side release prep](#container-side-release-prep-optional) for details.

5. **Check the result**: `shared/build_version.txt` holds the new version number, and
   `output/restructure` holds the built, deployable code. The new tag has been pushed to
   `REPO_URL` (and `PROD_REPO_URL` if configured).

If you hit strange merge conflicts or Docker build errors, see
[Troubleshooting](#troubleshooting) below.

## What a build does

- gets the latest version from a specified remote branch in the _dev_ repo
- bundles and packages gems for production deployment in `vendor/cache`
- installs Javascript components based on the YARN packages in `yarn.lock`
- precompile Javascript and CSS assets from project code and YARN installed node_modules
- sets up an app database, and migrates it to the current version
- updates a section marked `## Unreleased` in the `CHANGELOG.md` to the new version and date
- run [Brakeman](https://brakemanscanner.org/) tests to enforce static code analysis
- run [bundle-audit](https://github.com/rubysec/bundler-audit) to prevent insecure gems being deployed
- runs a subset of the rspec tests to validate the build
- commits and pushes the built and tagged version back to the repo
  (and / or an alternative _production_ repo if specified)

## Configuration

Copy `shared/build-vars-sample.sh` to `shared/build-vars.sh` and edit it with your details -
`REPO_URL`, `DOCS_REPO_URL`, `APPS_REPO_URL`, `GIT_EMAIL`, `BUILD_GIT_BRANCH` and the `DB_*`
variables are the essentials; see the comments in the sample file for the rest (including the
optional [release prep](#container-side-release-prep-optional) variables).

- `PROD_REPO_URL` - commit the built version to a different _production_ repo, in addition to
  the _dev_ repo (`REPO_URL`).
- `ONLY_PUSH_TO_PROD_REPO=true` - don't push the built version back to the _dev_ repo at all.
- `ONLY_PUSH_ASSETS_TO_PROD_REPO=true` - don't push built assets (Javascript, CSS, packaged gems)
  to the _dev_ repo; they still go to the _production_ repo if one is configured.

Set up `shared/.netrc` with login credentials for any private git repos (the source repo and
optionally the production repo) so the container can clone/pull/push your code:

    machine github.com login mygithubid password myplaintextpassword
    machine hostname.of.prod.repo login prodrepouserid password anotherplaintextpassword

Protect it with `chmod 600 shared/.netrc`, or symlink your own `.netrc` if you already use one
for git auth: `ln -s ~/.netrc ./shared/.netrc`.

`shared/build-vars.sh` and `shared/.netrc` are gitignored - do not commit them.

## The Docker image

Build (or rebuild) it with:

    docker image build .

Or `./build.sh image` - cleans out any existing image and `output/restructure*`, then rebuilds
just the image (Ruby/Postgres/Node/etc, via `build-container.sh`) with `--no-cache`, without
running an actual ReStructure build. Useful for producing a fresh, dependencies-only image to
push to a registry (e.g. GitHub Packages) or upload to S3 - it doesn't need
`shared/build-vars.sh` or `shared/.netrc` to exist. It also saves a gzipped tarball to
`dist/restructure-build.tar.gz` (e.g. `aws s3 cp dist/restructure-build.tar.gz s3://your-bucket/path/`).

The Dockerfile does not `COPY` `shared/.netrc` or `shared/build-vars.sh` into the image - both are
only ever read at `docker run` time from the `shared/` volume mount (see `build.sh`), so the built
image itself contains no git credentials or repo/DB configuration and is safe to share/push to a
registry. If you have an older image built before this changed, rebuild with
`docker build --no-cache` rather than reusing it, and rotate any credentials it may have had baked in.

### Troubleshooting

You may need to clear the output directory to get started. `output/restructure*` is owned by
root (written by the container), so clean it up via a throwaway container rather than host sudo:

    docker run --rm --volume="$(pwd)/output:/output" consected/restructure-build sh -c 'rm -rf /output/restructure*'

Or just run `./build.sh clean`, which does this automatically - this (or clearing the output
directory) can also often resolve strange merge conflicts during a build.

If you get an error that yum can't find a repository due to no space, you may need to clean up docker. This will
clean everything!

    docker system prune -a
    docker volume rm $(docker volume ls -f dangling=true -q)

## Container-side release prep (optional)

By default the container only builds `BUILD_GIT_BRANCH` as it finds it, assuming release prep
(upstream fork sync, dependency updates, `CHANGELOG.md`/`version.txt` reconciliation, and merging
`FROM_BRANCH` into `BUILD_GIT_BRANCH`) already happened elsewhere, e.g. via
`app-scripts/release_and_build.sh` on a host checkout. Set `SKIP_RELEASE_PREP=false` in
`shared/build-vars.sh` to have this container perform that prep itself - see the commented
variables in `shared/build-vars-sample.sh` (`FROM_BRANCH`, `UPSTREAM_REPO_URL`,
`SKIP_UPSTREAM_SYNC`, `SKIP_DEP_UPDATE`, `MERGE_BACK`).

If the toolbox host doesn't have a full `restructure` checkout to read `.ruby-version` from, run
`shared/probe-ruby-version.sh` first to populate `shared/default-ruby-version.sh` from a cheap
sparse clone.

## Running Rails admin/maintenance commands

`shared/run-rails-command.sh` is a container entrypoint for running Rails commands against a
deployed release (checked out fresh from `RELEASES_REPO_URL` at `APPVER`), so a toolbox host
needs neither Ruby nor a `psql` client installed:

    docker run --rm -it \
      -v "${HOME}/.aws:/root/.aws:ro" \
      -e AWS_PROFILE -e AWS_ACCT -e AWS_REGION -e SECRETS_MGR_NAME \
      -e RELEASES_REPO_URL -e APPVER -e DB_NAME -e DB_HOST -e DB_SEARCH_PATH -e FILESTORE_SUBDIR_BASE \
      -v "$(pwd)/shared:/shared" \
      consected/restructure-build /shared/run-rails-command.sh migrate

Supported commands: `migrate`, `add-admin <email>`, `add-filestore-app <id> [dev]`, `psql`,
`console`. Secrets are always resolved from AWS Secrets Manager inside the container - nothing
sensitive is passed as a command-line argument.

## Toolbox CLI scripts

`toolbox/bin/*.sh` are project-agnostic, host-side wrapper scripts covering the whole build/deploy
toolchain (not just the build above) - `build_latest_version.sh`, `migrate_db.sh`,
`add_or_reset_admin.sh`, `add_filestore_app.sh`, `db_client.sh` (wrapping the Rails commands
above), plus deploy and toolbox-provisioning scripts. See
[toolbox/README.md](toolbox/README.md) for the full script reference and setup steps.

## License

BSD 3-Clause License

This code is property of Harvard University
and made available as open source under the BSD-3 license
(<https://opensource.org/licenses/BSD-3-Clause>).

Copyright 2020 Harvard University
