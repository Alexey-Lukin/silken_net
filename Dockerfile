# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t silken_net .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name silken_net silken_net

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Base image pinned by digest for supply-chain integrity. Dependabot (docker
# ecosystem, .github/dependabot.yml) bumps the tag AND the digest together — it
# cannot do that through an ARG-indirected FROM (dependabot-core #4597), so the
# tag is literal here. Keep the version in sync with .ruby-version.
FROM docker.io/library/ruby:4.0.6-slim@sha256:607bf92fa7ecebb4a0c6654b62cb44c48d94b36b6f5a754611ddbbe3dc5b6135 AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips postgresql-client && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
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

# Install Cloud SQL Auth Proxy for Akash Network connectivity.
# The proxy tunnels PostgreSQL traffic through Google Cloud API (outbound HTTPS),
# bypassing Akash's CAP_NET_ADMIN restriction (no VPN/Tailscale possible).
# Only activates when CLOUD_SQL_INSTANCE_CONNECTION_NAME is set in ENV.
# See: docs/06_02_Akash_Network_Integration.md
# --checksum = sha256 of the binary itself — a version-pinned URL alone trusts the
# bucket forever [INF.21]. 🔴 Where that hash comes from, because the obvious answer
# is wrong: the bucket publishes NO `.sha256` sidecar (404 for every version tried)
# and the GitHub release carries zero assets. The upstream release BODY holds a hash
# table, but only sometimes — v2.25.0/v2.25.1/v2.25.4 have none, weeks after publish.
# So the reproducible source is the bucket itself:
#   curl -sSf <url above> | shasum -a 256
# Verify the method with a positive control before trusting it — recomputing the
# PREVIOUS pin must reproduce it byte-for-byte, or the recipe, not the release, moved.
# Dependabot cannot see an `ADD --checksum` URL (its docker ecosystem tracks the base
# image tag+digest only), so this pin moves by hand or not at all [OPS.10].
ADD --checksum=sha256:f0584d79e877a8a46300fe2513840972c44e704c15dc3da6a49d5408f7d6f233 https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.25.3/cloud-sql-proxy.linux.amd64 /usr/local/bin/cloud-sql-proxy
RUN chmod +x /usr/local/bin/cloud-sql-proxy

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
