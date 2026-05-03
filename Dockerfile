# Slice 11b — Phoenix Docker release for Gigalixir deploy.
#
# Multi-stage: a builder image fetches deps + builds assets + assembles
# the OTP release; a slim runtime image then copies only the release
# artifact + the runtime libraries it needs. The runtime image carries
# no Elixir / Erlang build tools and no application source code beyond
# what's inside the release tarball.
#
# Versions match `.tool-versions`. Bump them here when the local versions
# move; CI runs against the same matrix.

# ── BUILDER ──────────────────────────────────────────────────────────
ARG ELIXIR_VERSION=1.16.3
ARG OTP_VERSION=26.2.5
ARG DEBIAN_VERSION=bookworm-20240701-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# Install build tooling needed by the release: git for some Hex deps,
# build-essential for any C-based deps Postgrex pulls in.
RUN apt-get update -y \
  && apt-get install -y --no-install-recommends \
       build-essential \
       git \
  && apt-get clean \
  && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

ENV MIX_ENV="prod"
ENV LANG=C.UTF-8
ENV LANGUAGE=C.UTF-8
ENV LC_ALL=C.UTF-8

# Hex / Rebar in this image
RUN mix local.hex --force && mix local.rebar --force

# Copy lockfile + manifest first so Docker can cache the deps fetch
# layer when application code changes but deps don't.
COPY mix.exs mix.lock ./
COPY config/config.exs config/${MIX_ENV}.exs config/

RUN mix deps.get --only ${MIX_ENV}
RUN mix deps.compile

# Application source + assets pipeline.
COPY priv priv
COPY lib lib
COPY assets assets

# `mix assets.deploy` runs Tailwind + esbuild minification and digest.
RUN mix assets.deploy

# Compile the application (after assets so the digest cache is in place).
RUN mix compile

# `runtime.exs` is read at boot; keep it in the release.
COPY config/runtime.exs config/

# Optional release overlays (bin scripts from `mix phx.gen.release`).
COPY rel rel

# Assemble the release into _build/prod/rel/ideajar.
RUN mix release

# ── RUNTIME ──────────────────────────────────────────────────────────
FROM ${RUNNER_IMAGE} AS runner

# Slim runtime: only the libs Erlang needs at runtime.
RUN apt-get update -y \
  && apt-get install -y --no-install-recommends \
       libstdc++6 \
       openssl \
       libncurses5 \
       locales \
       ca-certificates \
  && apt-get clean \
  && rm -f /var/lib/apt/lists/*_* \
  && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody /app

# Don't run the release as root.
USER nobody

ENV MIX_ENV="prod"

# Copy the assembled release from the builder.
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/ideajar ./

# Gigalixir routes traffic to the port advertised via $PORT (defaults
# to 4000 in `runtime.exs` if unset).
EXPOSE 4000

CMD ["/app/bin/server"]
