alpine_version := "3.21"
elixir_version := `mise current elixir | cut -d'.' -f1,2`
otp_version := `mise current erlang | cut -d'.' -f1`

container_engine := `command -v podman >/dev/null 2>&1 && echo podman || echo docker`
compose_cmd := `command -v docker-compose >/dev/null 2>&1 && echo "docker-compose" || (command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 && echo "docker compose" || echo "podman-compose")`

build-image engine=container_engine:
	#!/usr/bin/env bash
	set -euo pipefail
	echo "Using container engine: {{engine}}"
	echo "Building Exoforge with Elixir {{elixir_version}} and OTP {{otp_version}}..."
	FORMAT_ARGS=()
	if [ "{{engine}}" = "podman" ]; then
		FORMAT_ARGS+=(--format docker)
	fi
	{{engine}} build "${FORMAT_ARGS[@]}" \
		--build-arg ELIXIR_VERSION={{elixir_version}} \
		--build-arg OTP_VERSION={{otp_version}} \
		--build-arg ALPINE_VERSION={{alpine_version}} \
		-t exoforge/core:latest .

# Run all test suites across Core, Plugins, System, and C# SDK
test: test-core test-plugins test-system test-sdk

# Test Exoforge core kernel
test-core:
	(cd core && mix test)

# Test standard plugins
test-plugins:
	(cd plugins/exoforge_std_database && mix test)
	(cd plugins/exoforge_std_auth && mix test)
	(cd plugins/exoforge_std_player_data && mix test)
	(cd plugins/exoforge_std_http && mix test)
	(cd plugins/exoforge_std_ws && mix test)
	(cd plugins/exoforge_std_dashboard && mix test)

# Test root system integration
test-system:
	mix test

# Build C# WASM plugins
build-wasm:
	./plugins_csharp/combat_wasm/build.sh

# Run C# SDK unit tests (Client & Plugin SDK)
test-sdk:
	dotnet test sdk/csharp/Exoforge.Client.Tests
	dotnet test sdk/csharp/Exoforge.Plugin.SDK.Tests

# Start backend dev server
dev:
	mix run --no-halt

# Run end-to-end integration test
test-e2e: build-wasm
	#!/usr/bin/env bash
	set -euo pipefail
	echo "Starting Exoforge backend..."
	mix run --no-halt &
	SERVER_PID=$!
	trap "kill $SERVER_PID 2>/dev/null || true" EXIT
	echo "Waiting for port 4000..."
	for i in $(seq 1 40); do
		if nc -z 127.0.0.1 4000 2>/dev/null; then
			break
		fi
		sleep 0.2
	done
	echo "Running C# client E2E test against live backend..."
	dotnet test sdk/csharp/Exoforge.Client.Tests
	echo "E2E vertical slice passed successfully!"

# Run backend in production mode (foreground)
prod: build-wasm
	MIX_ENV=prod mix run --no-halt

# Assemble standalone OTP production release
release: build-wasm
	MIX_ENV=prod mix release --overwrite

# Run standalone production release (daemon in background)
run-release: release
	_build/prod/rel/exoforge/bin/exoforge start

# Run standalone production release (interactive console)
console-release: release
	_build/prod/rel/exoforge/bin/exoforge console

# Stop standalone production release daemon
stop-release:
	_build/prod/rel/exoforge/bin/exoforge stop

# Build production container image
docker-build: build-wasm
	{{container_engine}} build -t exoforge:latest .

# Run full stack with PostgreSQL using Docker / Podman Compose
compose-up: build-wasm
	{{compose_cmd}} up -d --build

# Follow logs from all Compose services
compose-logs:
	{{compose_cmd}} logs -f

# Stop and tear down Compose services and networks
compose-down:
	{{compose_cmd}} down

# Restart Compose stack
compose-restart: compose-down compose-up

# Start only the local PostgreSQL 16 database container
postgres-up:
	{{compose_cmd}} up -d postgres

# Stop the local PostgreSQL 16 database container
postgres-down:
	{{compose_cmd}} stop postgres

# Deploy to local or remote Kubernetes cluster via Kustomize
k8s-deploy:
	kubectl apply -k deploy/k8s

# Teardown Kubernetes resources
k8s-destroy:
	kubectl delete -k deploy/k8s

# Run cluster and entity runtime performance benchmark
benchmark:
	mix test test/cluster_benchmark_test.exs

