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
	echo "[clean-build] exporting HEAD"
	git archive HEAD | tar -x -C "$work"
	echo "[clean-build] building the engine-agnostic libraries into the package"
	just build-unity-sdk "$work"

	echo "[clean-build] building the SDK from a cold tree"
	MSBUILDDISABLENODEREUSE=1 dotnet build "$work/sdk/csharp/Exoforge.CLI" --nologo -v q
	echo "[clean-build] building a plugin"
	MSBUILDDISABLENODEREUSE=1 dotnet run --project "$work/sdk/csharp/Exoforge.CLI" -- plugin build snake_leaderboard --dir "$work/sdk/unity/sample_unity/Exoforge"
	# Every runtime the kernel can host, not just the one. This path was only reachable through
	# recipes needing Docker or a live server, so it rotted: the sample's build.sh still looked for
	# the manifest generator where it lived before M29, and took build-wasm down with it.
	echo "[clean-build] building a WASM plugin"
	"$work/plugins_csharp/sample_wasm/build.sh"
	test -f "$work/plugins_csharp/sample_wasm/sample_wasm.wasm"
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

# Test C# SDKs (Client, Plugin SDK, Generator & Management Engine)
test-sdk:
	dotnet test sdk/csharp/Exoforge.Client.Tests
	dotnet test sdk/csharp/Exoforge.Plugin.SDK.Tests
	dotnet test sdk/csharp/Exoforge.Plugin.Generator.Tests
	dotnet test sdk/csharp/Exoforge.Management.Tests
	# A WASM plugin's assembly is a contract, not a host process: it has no dispatch table and no
	# entry point of its own, so compiling one is the check that the generator still agrees.
	dotnet build plugins_csharp/sample_wasm/sample_wasm.csproj -v q --nologo

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

# Private: stop Unity and clear its lockfile, so a batch run starts from a known state.
_unity-reset:
	#!/usr/bin/env bash
	pkill -f "Unity.app/Contents/MacOS/Unity" 2>/dev/null || true
	sleep 1
	rm -f {{SAMPLE}}/Temp/UnityLockfile

# Rebuild the sample scene (idempotent)
sample-setup: build-unity-sdk _unity-reset
	@{{UNITY}} -batchmode -quit -nographics -projectPath "$(pwd)/{{SAMPLE}}" -executeMethod ExoforgeSampleSetup.SetUp -logFile /tmp/exoforge-sample-setup.log; status=$?; grep -E "ExoforgeSample\]" /tmp/exoforge-sample-setup.log || true; exit $status

# Play mode, because Awake does not run in the editor — the session lifecycle is inert there.
# Run the sample's play-mode tests (session lifecycle)
sample-play-tests: build-unity-sdk _unity-reset
	#!/usr/bin/env bash
	set -euo pipefail
	rm -f /tmp/exoforge-play-tests.xml
	"{{UNITY}}" -batchmode -nographics -projectPath "$(pwd)/{{SAMPLE}}" \
		-runTests -testPlatform PlayMode \
		-testResults /tmp/exoforge-play-tests.xml \
		-logFile /tmp/exoforge-play-tests.log
	python3 -c "import xml.etree.ElementTree as E; r=E.parse('/tmp/exoforge-play-tests.xml').getroot(); print('  tests=%s passed=%s failed=%s' % (r.get('testcasecount'), r.get('passed'), r.get('failed')))"

# Headless self-check for the sample (board pixel maths + leaderboard parsing)
sample-check: build-unity-sdk _unity-reset
	@{{UNITY}} -batchmode -nographics -projectPath "$(pwd)/{{SAMPLE}}" -executeMethod ExoforgeSampleCheck.Run -logFile /tmp/exoforge-sample-check.log; status=$?; grep -E "ExoforgeSampleCheck\]" /tmp/exoforge-sample-check.log || true; exit $status

# ---- Unity SDK Package ----

# Starts the backend, deploys the sample plugin, runs the tests, stops the server again.
# Play-mode tests against a live cluster: the engine-side path, end to end
sample-live-tests: build-unity-sdk
	#!/usr/bin/env bash
	set -euo pipefail
	pkill -f "mix run" 2>/dev/null || true
	sleep 1

	mix run --no-halt > /tmp/exoforge-live-tests-server.log 2>&1 &
	server=$!
	# Kill the BEAM too, not just the wrapper: `kill` on `mix run` can leave it holding port 4000,
	# and then the offline play-mode tests run against a half-dead server instead of skipping.
	trap 'kill $server 2>/dev/null || true; pkill -f "mix run" 2>/dev/null || true; pkill -f beam.smp 2>/dev/null || true' EXIT

	for _ in $(seq 1 60); do
		nc -z 127.0.0.1 4000 2>/dev/null && break
		sleep 0.5
	done

	echo "[sample-live-tests] deploying the sample plugin"
	(cd {{SAMPLE}} && dotnet run --project ../../../sdk/csharp/Exoforge.CLI -- plugin push snake_leaderboard >/dev/null)

	just sample-play-tests


# Build the engine-agnostic C# libraries into the Unity package as binaries.
#
# The client and the tooling are not Unity-specific, so they are not Unity's to own. Each engine SDK
# ships them as a compiled assembly, which keeps the package purely engine-specific and means the
# next engine (Unreal, Godot) reuses the same libraries rather than reimplementing them.
#
# A build step rather than committed binaries: a checked-in DLL is a copy that can silently go stale,
# which is the same failure a synced source file has.
# Build the engine-agnostic C# libraries into the Unity package
build-unity-sdk root=".":
	#!/usr/bin/env bash
	set -euo pipefail
	root="${1:-.}"
	out="$root/sdk/csharp"

	# Where each library lands is decided by the staging hook in Directory.Build.targets, by project
	# name, so this is only a build and the copies happen on the way past. Release, because the
	# package ships what a game runs.
	dotnet build "$out/Exoforge.Client" -c Release --nologo -v q
	dotnet build "$out/Exoforge.Management" -c Release --nologo -v q

	# The generator ships inside the package too, under Editor/Plugins/Tools~. It has to live under a
	# `~` folder: Unity would otherwise load it as one of its own assemblies, and it references
	# Roslyn.
	dotnet build "$out/Exoforge.Plugin.Generator" -c Release --nologo -v q

	echo "[build-unity-sdk] sdk/unity/Exoforge.SDK Runtime/Plugins + Editor/Plugins staged"


# Pack the plugin SDK into the local feed. The package carries the attributes a plugin compiles
# against and the generator that writes its manifest, so a plugin outside this repository needs one
# PackageReference and no paths - see NuGet.config for how the feed is found.
pack-sdk:
	#!/usr/bin/env bash
	set -euo pipefail
	rm -rf dist/nuget
	mkdir -p dist/nuget
	dotnet pack sdk/csharp/Exoforge.Plugin.SDK -c Release -o dist/nuget --nologo -v q
	echo "[pack-sdk] local feed:"
	ls -1 dist/nuget


# The Unity package's own sources (Runtime/*.cs, Editor/*.cs) are the real thing - nothing outside
# the package compiles them, so there is no second copy to keep in step. What it does not own is the
# compiled libraries it ships, which is what build-unity-sdk stages into it.

# Force Unity to re-read the package (clears the import caches the editor builds up)
unity-reimport: build-unity-sdk _unity-reset
	#!/usr/bin/env bash
	set -euo pipefail
	project=sdk/unity/sample_unity
	rm -rf "$project/Library/ScriptAssemblies" "$project/Library/Bee" \
	       "$project/Library/ArtifactDB" "$project/Library/ArtifactDB-lock" \
	       "$project/Library/SourceAssetDB" "$project/Library/SourceAssetDB-lock"
	echo "[unity-reimport] import caches cleared — Unity recompiles on next open"

# Slow — creates a Unity project and runs a NativeAOT publish — but it is the only check that
# tests what a consumer actually does.
# Prove a new Unity project can install the package and build a plugin with no Exoforge checkout
clean-room-sdk:
	#!/usr/bin/env bash
	set -euo pipefail
	work=$(mktemp -d)
	trap 'rm -rf "$work"' EXIT

	echo "[clean-room] packing the SDK"
	just pack-unity >/dev/null
	tarball=$(ls dist/com.exoforge.sdk-*.tgz | head -1)

	echo "[clean-room] packing Exoforge.Plugin.SDK to the local feed"
	just pack-sdk >/dev/null

	echo "[clean-room] creating a Unity project at $work/Game"
	"{{UNITY}}" -batchmode -quit -createProject "$work/Game" -logFile "$work/create.log" >/dev/null

	echo "[clean-room] installing the package from the tarball"
	mkdir -p "$work/unpack"
	tar -xzf "$tarball" -C "$work/unpack"
	mv "$work/unpack/package" "$work/Game/Packages/com.exoforge.sdk"

	mkdir -p "$work/Game/Assets/Editor"
	cp sdk/unity/clean-room-probe.cs "$work/Game/Assets/Editor/CleanRoomProbe.cs"

	echo "[clean-room] running the first-run flow"
	EXOFORGE_FEED="$PWD/dist/nuget" "{{UNITY}}" -batchmode -nographics \
		-projectPath "$work/Game" -executeMethod CleanRoomProbe.Run \
		-logFile "$work/run.log" || {
			grep -E "\[clean-room\]|error " "$work/run.log" | head -20
			echo "[clean-room] FAILED — full log: $work/run.log"
			exit 1
		}

	grep -E "\[clean-room\]" "$work/run.log" | tail -3

# ---- Unity SDK Distribution ----

# Package Unity SDK into a self-contained UPM tarball (.tgz) for game developers
pack-unity:
	#!/usr/bin/env bash
	set -euo pipefail
	VERSION=$(grep '"version"' sdk/unity/Exoforge.SDK/package.json | head -1 | awk -F'"' '{print $4}')
	echo "Packaging Exoforge Unity SDK v${VERSION}..."
	just build-unity-sdk
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
	offenders=$(grep -rIn --exclude-dir=bin --exclude-dir=obj \
		-e '"sdk", *"csharp"' -e '"csharp", *"Exoforge' -e '"Exoforge\.Management", *"Tools~"' \
		dist/package || true)

	if [ -n "$offenders" ]; then
		echo "[Exoforge] FAILED: the package resolves paths into this repository's layout:"
		echo "$offenders"
		exit 1
	fi
	echo "[Exoforge] Package is self-contained."

	echo "Ready to import in Unity: Window > Package Manager > [+] > Add package from tarball..."

