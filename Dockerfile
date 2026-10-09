ARG ELIXIR_VERSION=1.20
ARG OTP_VERSION=29
# Must match the builder's Alpine, which is the one the BEAM release was compiled against. At 3.21 the
# runner shipped openssl 3.3.7 while the builder had 3.5.8, and OTP 29's crypto NIF needs 3.4 or newer:
# the container died on boot with "EVP_PKEY_sign_message_init: symbol not found".
ARG ALPINE_VERSION=3.24

ARG MIX_ENV=prod

# ---------------------------------------------------------------------
# Stage 1: Build & assemble release
# ---------------------------------------------------------------------
FROM docker.io/library/elixir:${ELIXIR_VERSION}-otp-${OTP_VERSION}-alpine AS builder

ARG MIX_ENV=prod
ENV MIX_ENV=${MIX_ENV} \
    LANG=C.UTF-8

# Plugins are framework-dependent .NET assemblies, so building one needs the SDK and running one
# needs the runtime. Both come from the official images rather than from Alpine's repositories, which
# lag the SDK version a plugin targets.
ARG DOTNET_SDK_IMAGE=mcr.microsoft.com/dotnet/sdk:10.0-alpine
ARG DOTNET_RUNTIME_IMAGE=mcr.microsoft.com/dotnet/runtime:10.0-alpine

RUN apk add --no-cache build-base git curl \
    libstdc++ icu-libs krb5-libs zlib libgcc

COPY --from=${DOTNET_SDK_IMAGE} /usr/share/dotnet /usr/share/dotnet
ENV DOTNET_ROOT=/usr/share/dotnet \
    PATH=${PATH}:/usr/share/dotnet

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

# Re-declared: an ARG is scoped to the stage that declares it, so the builder's copy is not visible
# here and `COPY --from=` resolves to nothing.
ARG DOTNET_RUNTIME_IMAGE=mcr.microsoft.com/dotnet/runtime:10.0-alpine

ENV LANG=C.UTF-8 \
    MIX_ENV=prod \
    ERL_EPMD_PORT=4369 \
    PORT=4005 \
    DASHBOARD_PORT=4005 \
    GATEWAY_PORT=4000 \
    HTTP_PORT=4001 \
    PHX_HOST=localhost

# BEAM's own dependencies, plus what the .NET runtime needs to load a plugin assembly.
RUN apk add --no-cache libstdc++ ncurses-libs openssl ca-certificates curl \
    icu-libs krb5-libs zlib libgcc

# The runtime only: a plugin ships IL and its dependencies, and nothing in the plugin carries a
# runtime of its own.
COPY --from=${DOTNET_RUNTIME_IMAGE} /usr/share/dotnet /usr/share/dotnet
ENV DOTNET_ROOT=/usr/share/dotnet \
    PATH=${PATH}:/usr/share/dotnet

WORKDIR /app

# Non-root user for security (essential for Kubernetes runAsNonRoot)
RUN addgroup -S exoforge && adduser -S exoforge -G exoforge && \
    mkdir -p /app/plugins_csharp /app/plugins_elixir && \
    chown -R exoforge:exoforge /app

# Copy assembled OTP release
COPY --from=builder --chown=exoforge:exoforge /build/_build/prod/rel/exoforge ./

# Copy plugin manifests. The built assemblies are not here: a plugin is deployed with `exo plugin
# build`/`push` rather than baked into the image, and the binary is a build output.
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
