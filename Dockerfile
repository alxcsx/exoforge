ARG ELIXIR_VERSION=1.20
ARG OTP_VERSION=29
ARG ALPINE_VERSION=3.21

ARG MIX_ENV=prod

# Build
FROM docker.io/library/elixir:${ELIXIR_VERSION}-otp-${OTP_VERSION}-alpine AS builder

ARG MIX_ENV
ENV MIX_ENV=${MIX_ENV} \
    LANG=C.UTF-8

RUN apk add --no-cache build-base git
WORKDIR /build

RUN mix local.hex --force && \
    mix local.rebar --force

COPY mix.exs mix.lock* ./
COPY config/ config/
COPY core/ core/
COPY lib/ lib/

RUN mix deps.get --only ${MIX_ENV} && \
    mix deps.compile && \
    mix compile && \
    mix release

# Runtime
FROM docker.io/library/alpine:${ALPINE_VERSION} AS runner

ENV LANG=C.UTF-8 \
    ERL_EPMD_PORT=4369 \
    ELIXIR_ERL_OPTIONS="-kernel inet_dist_listen_min 9000 -kernel inet_dist_listen_max 9000"

RUN apk add --no-cache libstdc++ ncurses-libs openssl

WORKDIR /app

RUN addgroup -S exoforge && adduser -S exoforge -G exoforge && \
    mkdir -p /plugins && \
    chown exoforge:exoforge /plugins

COPY --from=builder --chown=exoforge:exoforge /build/_build/prod/rel/exoforge ./

USER exoforge

EXPOSE 4000 4369 9000 63427

CMD ["/app/bin/exoforge", "start"]
