# syntax=docker/dockerfile:1

ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27.3
ARG DEBIAN_VERSION=bookworm

ARG BUILDER_IMAGE=hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}-20250224-slim
ARG RUNNER_IMAGE=debian:${DEBIAN_VERSION}-slim

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update && \
  apt-get install -y --no-install-recommends build-essential git ca-certificates && \
  rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

RUN mix assets.deploy
RUN mix compile
RUN mix release

FROM ${RUNNER_IMAGE} AS runner

RUN apt-get update && \
  apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 sqlite3 ca-certificates && \
  rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mkdir -p /app/data

ENV MIX_ENV=prod \
  PHX_SERVER=true \
  DATABASE_PATH=/app/data/w_core.sqlite3 \
  PORT=4000

COPY --from=builder /app/_build/prod/rel/w_core ./

EXPOSE 4000
VOLUME ["/app/data"]

CMD ["sh", "-c", "bin/w_core eval \"Ecto.Migrator.with_repo(WCore.Repo, &Ecto.Migrator.run(&1, :up, all: true))\" && exec bin/w_core start"]
