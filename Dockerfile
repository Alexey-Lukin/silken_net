# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t silken_net .
# docker run -d -p 80:80 -e SECRET_KEY_BASE=<value> --name silken_net silken_net
#   (the image ships no credentials.yml.enc — SEC.22 — so RAILS_MASTER_KEY would decrypt nothing)

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Base image pinned by digest for supply-chain integrity. Dependabot (docker
# ecosystem, .github/dependabot.yml) bumps the tag AND the digest together — it
# cannot do that through an ARG-indirected FROM (dependabot-core #4597), so the
# tag is literal here. Keep the version in sync with .ruby-version.
FROM docker.io/library/ruby:4.0.6-slim@sha256:58479f164d5947f852da27a4436c89bb986a811f959c40552bc7f6ccaabcc9c9 AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips postgresql-client && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
# 🔴 BUNDLE_WITHOUT lists BOTH groups on purpose, and "development" alone is not a
# smaller version of this — it is a no-op for most of what it looks like it excludes.
# Bundler drops a gem only when EVERY group it belongs to is in the without-list
# (`Definition#requested_groups`), and eleven of our gems — rspec-rails among them —
# sit in a SHARED `group :development, :test` block. Measured 2026-08-28: the
# single-group form shipped fifteen dev/test gems into the public image while
# reading as if it excluded them. If you ever narrow this list, re-run
# `docker run --rm <img> ls /usr/local/bundle/ruby/*/gems | grep -c rspec` — the
# claim is only as good as that count.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems.
# autoconf/automake/libtool: rbsecp256k1 (pulled by eth) vendors libsecp256k1
# and runs its autogen.sh → autoreconf during the native build. Without autotools
# the gem dies with "autoreconf: not found" and the whole image fails to build.
# These live only in this throw-away build stage — the final image (FROM base,
# below) copies just the compiled gems, so nothing here bloats the runtime image.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config autoconf automake libtool && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile




# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
