# Build ReStructure

A Dockerfile and scripts to build [ReStructure](https://github.com/consected/restructure) and
commit it to a repository. Deployable code is made available, and the latest version
(in the source `version.txt`) will be upversioned.

## Standalone server walkthrough: merge upstream and build a new version

This is the concrete, ordered set of steps for a fresh standalone server building a new version
of `restructure` (merging in upstream changes first). Nothing else on this host is required.

1. **Prerequisites**: `docker` and `git` installed. (`awscli` is only needed later for
   `shared/run-rails-command.sh` - not for building.)

2. **Get this repo**:

       git clone https://github.com/consected/restructure-build
       cd restructure-build

3. **Configure the build**:

       cp shared/build-vars-sample.sh shared/build-vars.sh

   Edit `shared/build-vars.sh` and set at least `REPO_URL`, `DOCS_REPO_URL`, `APPS_REPO_URL`,
   `GIT_EMAIL`, and the DB_* values (see the comments in the sample file). To have this run merge
   upstream changes into `FROM_BRANCH` before building, also set:

       SKIP_RELEASE_PREP=false
       FROM_BRANCH=develop
       UPSTREAM_REPO_URL="https://github.com/consected/restructure"

4. **Set up git credentials** the container will use to clone/push:

       cp ~/.netrc shared/.netrc   # or create it - see "Configuration" below
       chmod 600 shared/.netrc

5. **Merge upstream changes and build**:

       toolbox/bin/build_latest_version.sh

   The first run builds the `consected/restructure-build` Docker image (slow), then runs the
   build. With `SKIP_RELEASE_PREP=false` this performs the upstream sync, dependency update,
   `CHANGELOG.md`/`version.txt` reconciliation, and merge of `FROM_BRANCH` into `BUILD_GIT_BRANCH`
   itself (in a throwaway clone that is pushed straight to `origin` - there is no persistent local
   checkout of `restructure` on this host), then runs the existing build/test/tag/push pipeline.

   Equivalently, you can run `./build.sh` directly - `build_latest_version.sh` only adds the
   Docker/`build-vars.sh` sanity checks and a `shared/probe-ruby-version.sh` step first, which
   updates `shared/default-ruby-version.sh` to match the target branch's `.ruby-version` (a
   version is already checked into this repo, so this step is optional, not a hard requirement).

6. **Check the result**: `shared/build_version.txt` holds the new version number, and
   `output/restructure` holds the built, deployable code. The new tag has been pushed to
   `REPO_URL` (and `PROD_REPO_URL` if configured).

If you hit strange merge conflicts or Docker build errors, see the troubleshooting notes under
"Setup the Docker image" below.

## The Process

The build process performs the following

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

The Dockerfile does not `COPY` `shared/.netrc` or `shared/build-vars.sh` into the image - both are
only ever read at `docker run` time from the `shared/` volume mount (see `build.sh`), so the built
image itself contains no git credentials or repo/DB configuration and is safe to share/push to a
registry. If you have an older image built before this changed, rebuild with
`docker build --no-cache` rather than reusing it, and rotate any credentials it may have had baked in.

## Setup the Docker image

    docker image build .

Or `./build.sh image` - cleans out any existing image and `output/restructure*`, then rebuilds
just the image (Ruby/Postgres/Node/etc, via `build-container.sh`) with `--no-cache`, without
running an actual ReStructure build. Useful for producing a fresh, dependencies-only image to
push to a registry (e.g. GitHub Packages) - it doesn't need `shared/build-vars.sh` or
`shared/.netrc` to exist, and (per "Configuration" below) the image itself never contains either.
It also saves a gzipped tarball to `dist/restructure-build.tar.gz` (e.g. for uploading to S3 with
`aws s3 cp dist/restructure-build.tar.gz s3://your-bucket/path/`).

You may need to clear the output directory to get started. `output/restructure*` is owned by
root (written by the container), so clean it up via a throwaway container rather than host sudo:

    docker run --rm --volume="$(pwd)/output:/output" consected/restructure-build sh -c 'rm -rf /output/restructure*'

Or just run `./build.sh clean`, which does this automatically.

If you receive strange merge conflicts during build, this can also often resolve them.

If you get an error that yum can't find a repository due to no space, you may need to clean up docker. This will
clean everything!

    docker system prune -a
    docker volume rm $(docker volume ls -f dangling=true -q)

## Configuration

Copy `build-vars-sample.sh` to `build-vars.sh` and edit it with your details.

To commit the built version to a different _production_ repo, specify the `PROD_REPO_URL`
environment variable with the URL to the repo.

To prevent the built version being pushed to the _dev_ repo, specify `ONLY_PUSH_TO_PROD_REPO=true`

To prevent built assets (Javascript, CSS, packaged gems) being pushed to the _dev_ repo,
specify `ONLY_PUSH_ASSETS_TO_PROD_REPO=true`. They will continue to be pushed to the _production_
repo if it is being used.

Set up a file `shared/.netrc` to include login credentials to any private git repos (the original source
and optionally the production repo) to allow the container to clone, pull and push your code. The file
contents should look like:

    machine github.com login mygithubid password myplaintextpassword
    machine hostname.of.prod.repo login prodrepouserid password anotherplaintextpassword

Protect the plaintext file with:

    chmod 600 shared/.netrc

If you use `.netrc` for your git authentication anyway, then a symlink will suffice:

    ln -s ~/.netrc ./shared/.netrc

Ensure that `build-vars.sh` and `.netrc` are not committed to source control. Check the `.gitignore` file.

Build the container with:

    ./build.sh

## Run a build

Run the build process according to the settings in `shared/build-vars.sh` with:

    ./build.sh

On a successful build, the `output` directory will contain a sub-directory `restructure`
containing built and deployable code. The file `shared/build_version.txt` will show the new version.

### Container-side release prep (optional)

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
      -e RELEASES_REPO_URL -e APPVER -e DB_NAME -e DB_HOST -e DB_SEARCH_PATH \
      -v "$(pwd)/shared:/shared" \
      consected/restructure-build /shared/run-rails-command.sh migrate

Supported commands: `migrate`, `add-admin <email>`, `add-filestore-app <id> [dev]`, `psql`,
`console`. Secrets are always resolved from AWS Secrets Manager inside the container - nothing
sensitive is passed as a command-line argument.

See [toolbox/docs/onboarding.md](toolbox/docs/onboarding.md) for a project-agnostic set of
host-side wrapper scripts (`toolbox/bin/`) that call this entrypoint, plus the rest of the
build/deploy toolchain.

## License

BSD 3-Clause License

This code is property of Harvard University
and made available as open source under the BSD-3 license
(<https://opensource.org/licenses/BSD-3-Clause>).

Copyright 2020 Harvard University
