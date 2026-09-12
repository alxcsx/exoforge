alpine_version := "3.21"
elixir_version := `mise current elixir | cut -d'.' -f1,2`
otp_version := `mise current erlang | cut -d'.' -f1`

container_engine := `command -v podman >/dev/null 2>&1 && echo podman || echo docker`

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
