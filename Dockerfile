ARG ELIXIR_VERSION=1.20
ARG OTP_VERSION=29
ARG ALPINE_VERSION=3.21

ARG MIX_ENV=prod

# ---------------------------------------------------------------------
# Stage 1: Build & assemble release
# ---------------------------------------------------------------------
FROM docker.io/library/elixir:${ELIXIR_VERSION}-otp-${OTP_VERSION}-alpine AS builder

ARG MIX_ENV=prod
ENV MIX_ENV=${MIX_ENV} \
    LANG=C.UTF-8

RUN apk add --no-cache build-base git curl

WORKDIR /build

RUN mix local.hex --force && \
    mix local.rebar --force

# Copy project definition, core, plugins, and configs
COPY mix.exs mix.lock* ./
COPY config/ config/
COPY core/ core/
COPY plugins/ plugins/
COPY plugins_csharp/ plugins_csharp/
COPY lib/ lib/

# Fetch and compile dependencies, generate plugin manifests, and assemble OTP release
RUN mix deps.get --only ${MIX_ENV} && \
    mix deps.compile && \
    mix compile && \
    mix release

# ---------------------------------------------------------------------
# Stage 2: Minimal Production Runtime
# ---------------------------------------------------------------------
FROM docker.io/library/alpine:${ALPINE_VERSION} AS runner

ENV LANG=C.UTF-8 \
    MIX_ENV=prod \
    ERL_EPMD_PORT=4369 \
    PORT=4005 \
    DASHBOARD_PORT=4005 \
    GATEWAY_PORT=4000 \
    HTTP_PORT=4001 \
    PHX_HOST=localhost

# Install runtime dependencies for BEAM and WASM NIFs
RUN apk add --no-cache libstdc++ ncurses-libs openssl ca-certificates curl

WORKDIR /app

# Non-root user for security (essential for Kubernetes runAsNonRoot)
RUN addgroup -S exoforge && adduser -S exoforge -G exoforge && \
    mkdir -p /app/plugins_csharp /app/plugins_elixir && \
    chown -R exoforge:exoforge /app

# Copy assembled OTP release
COPY --from=builder --chown=exoforge:exoforge /build/_build/prod/rel/exoforge ./

# Copy plugin manifests and WASM binaries
COPY --from=builder --chown=exoforge:exoforge /build/plugins_csharp ./plugins_csharp
COPY --from=builder --chown=exoforge:exoforge /build/_build/prod/lib ./plugins_elixir

USER exoforge

# Exposed ports:
# 4005: Game Producer & Designer Studio (Phoenix LiveView)
# 4000: WebSocket Gateway (Real-time wire protocol)
# 4001: HTTP REST Ingress
# 4369: EPMD (BEAM clustering)
# 9000: BEAM node distribution
EXPOSE 4005 4000 4001 4369 9000

# Container / Kubernetes Healthcheck hitting Studio API
HEALTHCHECK --interval=5s --timeout=3s --retries=5 --start-period=5s \
  CMD curl -f http://localhost:4005/api/health || exit 1

CMD ["/app/bin/exoforge", "start"]
