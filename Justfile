# =====================================================================
# Exoforge Command Automation (Justfile)
# =====================================================================

container_engine := `command -v podman >/dev/null 2>&1 && echo podman || echo docker`
compose_cmd := `command -v docker-compose >/dev/null 2>&1 && echo "docker-compose" || (command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 && echo "docker compose" || echo "podman-compose")`

# ---- Development ----

# Run backend development server
dev:
	mix run --no-halt

# Stop the dev server and wipe all dev data (SQLite databases + uploaded plugins)
dev-reset:
	-@pkill -f "mix run" 2>/dev/null
	@find . -type d -path "*/priv/data" -not -path "*/_build/*" -prune -exec rm -rf {} +
	@echo "Development data cleared — SQLite databases and uploaded plugins are gone."

# Format all Elixir code
format:
	mix format

# ---- Testing ----

# Incremental builds hide a whole class of bug: missing project references, files that are
# gitignored but needed, package contents. Four tooling bugs in a row were this shape and every one
# of them built fine locally.
# Build the SDK and a plugin from a pristine export of HEAD
clean-build:
	#!/usr/bin/env bash
	set -euo pipefail
	work=$(mktemp -d)
	trap 'rm -rf "$work"' EXIT
	echo "[clean-build] checking the Unity package is in step with the C# sources"
	just check-unity-sdk

	echo "[clean-build] exporting HEAD"
	git archive HEAD | tar -x -C "$work"
	echo "[clean-build] building the SDK from a cold tree"
	MSBUILDDISABLENODEREUSE=1 dotnet build "$work/sdk/csharp/Exoforge.CLI" --nologo -v q
	echo "[clean-build] building a plugin"
	MSBUILDDISABLENODEREUSE=1 dotnet run --project "$work/sdk/csharp/Exoforge.CLI" -- plugin build snake_leaderboard --dir "$work/sdk/unity/sample_unity/Exoforge"
	test -f "$work/sdk/unity/sample_unity/Exoforge/plugins/snake_leaderboard/manifest.exs"
	echo "[clean-build] OK: the tree builds from a clean checkout"


# Run all test suites across Core, Plugins, System, and C# SDK
test: test-core test-plugins test-system test-sdk

# Test Exoforge core kernel
test-core:
	(cd core && mix test)

# Test all standard plugins
test-plugins:
	(cd plugins/exoforge_std_database && mix test)
	(cd plugins/exoforge_std_auth && mix test)
	(cd plugins/exoforge_std_player_data && mix test)
	(cd plugins/exoforge_std_http && mix test)
	(cd plugins/exoforge_std_ws && mix test)
	(cd plugins/exoforge_std_dashboard && mix test)
	(cd plugins/exoforge_std_dashboard_views && mix test)
	(cd plugins/exoforge_std_plugin_manager && mix test)

# Test root system integration
test-system:
	mix test

# Test C# SDKs (Client, Plugin SDK & Management Engine)
test-sdk:
	dotnet test sdk/csharp/Exoforge.Client.Tests
	dotnet test sdk/csharp/Exoforge.Plugin.SDK.Tests
	dotnet test sdk/csharp/Exoforge.Management.Tests

# Run live end-to-end integration test (Client -> WS :4000 -> WASM -> Event -> Client)
test-e2e: build-wasm
	#!/usr/bin/env bash
	set -euo pipefail
	pkill -f beam.smp 2>/dev/null || true
	sleep 0.5
	echo "Starting Exoforge backend..."
	mix run --no-halt &
	SERVER_PID=$!
	trap "pkill -P $SERVER_PID 2>/dev/null || true; kill $SERVER_PID 2>/dev/null || true; pkill -f beam.smp 2>/dev/null || true" EXIT
	echo "Waiting for ports 4000 and 4001..."
	for i in $(seq 1 40); do
		if nc -z 127.0.0.1 4000 2>/dev/null && nc -z 127.0.0.1 4001 2>/dev/null; then break; fi
		sleep 0.2
	done
	echo "Running C# client E2E test against live backend..."
	dotnet test sdk/csharp/Exoforge.Client.Tests
	echo "E2E vertical slice passed successfully!"

# Run cluster performance benchmark
benchmark:
	mix test test/cluster_benchmark_test.exs

# ---- Build & Release ----

# Build C# WASM plugins (e.g. just build-wasm, or just build-wasm sample_wasm)
build-wasm plugin="":
	#!/usr/bin/env bash
	set -euo pipefail
	if [ -n "{{plugin}}" ]; then
		[ -f "./plugins_csharp/{{plugin}}/build.sh" ] && ./plugins_csharp/{{plugin}}/build.sh
	else
		for script in plugins_csharp/*/build.sh; do
			[ -f "$script" ] && "$script"
		done
	fi

# Run backend in production mode (foreground)
prod: build-wasm
	# Local prod-mode run: opt in to SQLite explicitly (real deploys must set DATABASE_URL).
	SECRET_KEY_BASE="${SECRET_KEY_BASE:-$(mix phx.gen.secret)}" EXOFORGE_ALLOW_SQLITE_FALLBACK=true MIX_ENV=prod mix run --no-halt

# Assemble standalone OTP production release
release: build-wasm
	MIX_ENV=prod mix release --overwrite

# Run standalone production release (daemon)
run-release: release
	_build/prod/rel/exoforge/bin/exoforge start

# Run standalone production release (interactive console)
console-release: release
	_build/prod/rel/exoforge/bin/exoforge console

# Stop standalone production release daemon
stop-release:
	_build/prod/rel/exoforge/bin/exoforge stop

# ---- Containers & Kubernetes ----

# Build production container image
docker-build: build-wasm
	{{container_engine}} build -t exoforge:latest .

# Run full stack with PostgreSQL using Compose
compose-up: build-wasm
	{{compose_cmd}} up -d --build

# Follow Compose logs
compose-logs:
	{{compose_cmd}} logs -f

# Stop Compose services
compose-down:
	{{compose_cmd}} down

# Restart Compose stack
compose-restart: compose-down compose-up

# Start only local PostgreSQL container
postgres-up:
	{{compose_cmd}} up -d postgres

# Stop local PostgreSQL container
postgres-down:
	{{compose_cmd}} stop postgres

# Deploy to Kubernetes cluster via Kustomize (with sensible defaults)
k8s-deploy:
	#!/usr/bin/env bash
	set -euo pipefail
	DATABASE_URL="${DATABASE_URL:-postgres://postgres:postgres@postgres:5432/exoforge_prod}"
	POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
	SECRET_KEY_BASE="${SECRET_KEY_BASE:-$(mix phx.gen.secret 2>/dev/null || echo exoforge_secret_key_base_min_64_characters_long_for_dev_mode_testing)}"
	RELEASE_COOKIE="${RELEASE_COOKIE:-exoforge_cluster_cookie}"
	EXOFORGE_ADMIN_PASSWORD="${EXOFORGE_ADMIN_PASSWORD:-admin12345}"
	kubectl create namespace exoforge --dry-run=client -o yaml | kubectl apply -f -
	kubectl -n exoforge create secret generic exoforge-secrets \
		--from-literal=DATABASE_URL="$DATABASE_URL" \
		--from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
		--from-literal=SECRET_KEY_BASE="$SECRET_KEY_BASE" \
		--from-literal=RELEASE_COOKIE="$RELEASE_COOKIE" \
		--from-literal=EXOFORGE_ADMIN_PASSWORD="$EXOFORGE_ADMIN_PASSWORD" \
		--dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -k deploy/k8s

# Teardown Kubernetes resources
k8s-destroy:
	kubectl delete -k deploy/k8s

# ---- Unity Sample (CLI-driven) ----
# The sample scene is built from code, not hand-edited YAML. Everything runs headless.
UNITY := env_var_or_default("UNITY_PATH", "/Applications/Unity/Hub/Editor/6000.6.3f1/Unity.app/Contents/MacOS/Unity")
SAMPLE := "sdk/unity/sample_unity"

# Rebuild the sample scene (idempotent)
sample-setup:
	-@pkill -f "Unity.app/Contents/MacOS/Unity" 2>/dev/null
	@rm -f {{SAMPLE}}/Temp/UnityLockfile
	@{{UNITY}} -batchmode -quit -nographics -projectPath "$(pwd)/{{SAMPLE}}" -executeMethod ExoforgeSampleSetup.SetUp -logFile /tmp/exoforge-sample-setup.log; status=$?; grep -E "ExoforgeSample\]" /tmp/exoforge-sample-setup.log || true; exit $status

# Headless self-check for the sample (board pixel maths + leaderboard parsing)
sample-check:
	-@pkill -f "Unity.app/Contents/MacOS/Unity" 2>/dev/null
	@rm -f {{SAMPLE}}/Temp/UnityLockfile
	@{{UNITY}} -batchmode -nographics -projectPath "$(pwd)/{{SAMPLE}}" -executeMethod ExoforgeSampleCheck.Run -logFile /tmp/exoforge-sample-check.log; status=$?; grep -E "ExoforgeSampleCheck\]" /tmp/exoforge-sample-check.log || true; exit $status

# ---- Unity SDK Package Contents ----

# The Unity package shares sources with the C# libraries and must be self-contained on disk: a
# symlink out of the package is meaningless to a consumer who installed the tarball, and Unity
# cannot reliably tell when the *target* of a link changed. These are real files in the package,
# kept in step from the canonical sources.
unity_shared := "Runtime/ExoClient.cs:Exoforge.Client/ExoClient.cs Runtime/ExoDispatcher.cs:Exoforge.Client/ExoDispatcher.cs Runtime/ExoTransport.cs:Exoforge.Client/ExoTransport.cs Runtime/Protocol.cs:Exoforge.Client/Protocol.cs Runtime/IsExternalInit.cs:Exoforge.Client/IsExternalInit.cs Editor/Management/ExoDeployer.cs:Exoforge.Management/ExoDeployer.cs Editor/Management/ExoWorkspace.cs:Exoforge.Management/ExoWorkspace.cs Editor/Management/ExoScaffolder.cs:Exoforge.Management/ExoScaffolder.cs Editor/Management/ExoCodeGenerator.cs:Exoforge.Management/ExoCodeGenerator.cs"

# Copy the C# sources the Unity package shares, so the package stands alone
sync-unity-sdk:
	#!/usr/bin/env bash
	set -euo pipefail
	pkg=sdk/unity/Exoforge.SDK
	mgmt=sdk/csharp/Exoforge.Management

	for pair in {{unity_shared}}
	do
		dest="$pkg/${pair%%:*}"
		src="sdk/csharp/${pair#*:}"
		# Remove first: cp would otherwise write *through* an existing symlink into the source.
		rm -f "$dest"
		cp -L "$src" "$dest"
		echo "  ${pair%%:*} <- ${pair#*:}"
	done

	rm -rf "$pkg/Editor/Management/Tools~"
	cp -RL "$mgmt/Tools~" "$pkg/Editor/Management/Tools~"
	find "$pkg/Editor/Management/Tools~" -type d \( -name bin -o -name obj \) -prune -exec rm -rf {} +
	echo "  Editor/Management/Tools~ <- Exoforge.Management/Tools~"

	echo "[sync-unity-sdk] the package is self-contained"

# Fail when the Unity package has drifted from the C# sources it shares
check-unity-sdk:
	#!/usr/bin/env bash
	set -euo pipefail
	pkg=sdk/unity/Exoforge.SDK
	drift=0

	for pair in {{unity_shared}}
	do
		dest="$pkg/${pair%%:*}"
		src="sdk/csharp/${pair#*:}"
		if ! cmp -s "$dest" "$src"; then
			echo "  drifted: ${pair%%:*}"
			drift=1
		fi
	done

	if ! diff -r -q --exclude=bin --exclude=obj "$pkg/Editor/Management/Tools~" sdk/csharp/Exoforge.Management/Tools~ >/dev/null; then
		echo "  drifted: Editor/Management/Tools~"
		drift=1
	fi

	if [ "$drift" -ne 0 ]; then
		echo "[check-unity-sdk] FAILED: the Unity package drifted from the C# sources."
		echo "Run 'just sync-unity-sdk' and commit the result."
		exit 1
	fi

	echo "[check-unity-sdk] OK"

# ---- Unity SDK Distribution ----

# Package Unity SDK into a self-contained UPM tarball (.tgz) for game developers
pack-unity:
	#!/usr/bin/env bash
	set -euo pipefail
	VERSION=$(grep '"version"' sdk/unity/Exoforge.SDK/package.json | head -1 | awk -F'"' '{print $4}')
	echo "Packaging Exoforge Unity SDK v${VERSION}..."
	mkdir -p dist
	rm -rf dist/package dist/com.exoforge.sdk-*.tgz
	mkdir -p dist/package
	cp -RL sdk/unity/Exoforge.SDK/. dist/package/
	# The manifest generator ships as source; its build output should not.
	find dist/package -type d \( -name bin -o -name obj \) -prune -exec rm -rf {} +
	tar -czf "dist/com.exoforge.sdk-${VERSION}.tgz" -C dist package
	echo "[Exoforge] Created UPM package archive:"
	ls -lh "dist/com.exoforge.sdk-${VERSION}.tgz"
	# The package must stand alone: a consumer has no Exoforge checkout for a path to point at.
	# Match the code shapes that resolve into this repository, not prose that mentions it: a doc
	# comment explaining the rule is not a violation of it.
	if grep -rIn --exclude-dir=bin --exclude-dir=obj -e '"sdk", *"csharp"' -e '"csharp", *"Exoforge' -e '"Exoforge\.Management", *"Tools~"' dist/package >/dev/null 2>&1; then
		echo "[Exoforge] FAILED: the package resolves paths into this repository's layout:"
		grep -rIn --exclude-dir=bin --exclude-dir=obj -e '"sdk", *"csharp"' -e '"csharp", *"Exoforge' -e '"Exoforge\.Management", *"Tools~"' dist/package
		exit 1
	fi
	echo "[Exoforge] Package is self-contained."

	echo "Ready to import in Unity: Window > Package Manager > [+] > Add package from tarball..."

