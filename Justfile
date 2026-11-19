# =====================================================================
# Exoforge Command Automation (Justfile)
# =====================================================================

container_engine := `if command -v docker >/dev/null 2>&1; then echo docker; elif command -v podman >/dev/null 2>&1; then echo podman; else echo docker; fi`
compose_cmd := `if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then echo "docker compose"; elif command -v docker-compose >/dev/null 2>&1; then echo "docker-compose"; elif command -v podman-compose >/dev/null 2>&1; then echo "podman-compose"; elif command -v podman >/dev/null 2>&1 && podman compose version >/dev/null 2>&1; then echo "podman compose"; else echo "docker compose"; fi`

# ---- Development ----

# Run backend development server
dev: db-up
	DATABASE_URL="${DATABASE_URL:-postgres://postgres:postgres@127.0.0.1:5432/exoforge_prod}" mix run --no-halt

# Stop the dev server and wipe all dev data (local runtime data + uploaded extensions)
dev-reset:
	-@pkill -f "mix run" 2>/dev/null
	@find . -type d -path "*/priv/data" -not -path "*/_build/*" -prune -exec rm -rf {} +
	@echo "Development data cleared — local runtime data and uploaded extensions are gone."

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
	# Keep the workspace on failure. The log is the only thing that says why the probe threw, and
	# deleting it with the directory turns every failure into an identical blind re-run.
	trap 'status=$?; if [ $status -eq 0 ]; then rm -rf "$work"; else echo "[clean-room] kept $work"; fi; exit $status' EXIT
	echo "[clean-build] exporting HEAD"
	git archive HEAD | tar -x -C "$work"
	echo "[clean-build] building the engine-agnostic libraries into the package"
	just build-unity-sdk "$work"

	echo "[clean-build] building the SDK from a cold tree"
	MSBUILDDISABLENODEREUSE=1 dotnet build "$work/sdk/csharp/Exoforge.CLI" --nologo -v q
	echo "[clean-build] building an extension"
	MSBUILDDISABLENODEREUSE=1 dotnet run --project "$work/sdk/csharp/Exoforge.CLI" -- extension build snake_leaderboard --dir "$work/sdk/unity/sample_unity/Exoforge"
	# Every runtime the kernel can host, not just the one. This path was only reachable through
	# recipes needing Docker or a live server, so it rotted.
	echo "[clean-build] building the sample extension"
	ext_csharp="$work/extensions_csharp"
	MSBUILDDISABLENODEREUSE=1 dotnet run --project "$work/sdk/csharp/Exoforge.CLI" -- extension build sample_plugin --dir "$ext_csharp"
	test -f "$work/sdk/unity/sample_unity/Exoforge/extensions/snake_leaderboard/manifest.json"
	echo "[clean-build] OK: the tree builds from a clean checkout"


# Run all test suites across Core, Extensions, System, and C# SDK
test: test-core test-extensions test-system test-sdk

# Test Exoforge core kernel
test-core:
	(cd core && mix test)

# Test every standard extension. Each is its own Mix project with its own deps directory, and only the
# root's are fetched by a checkout: without `mix deps.get` here the first extension dies with "Unchecked
# dependencies for environment test" and the other seven never run.
test-extensions: db-up
	#!/usr/bin/env bash
	set -euo pipefail
	for dir in extensions/*/; do
		[ -d "$dir" ] && [ -f "$dir/mix.exs" ] || continue
		echo "== $dir"
		(cd "$dir" && mix deps.get >/dev/null && mix test)
	done

# Test root system integration
test-system: db-up build-extensions
	mix test

# Test C# SDKs (Client, Plugin SDK, Generator & Management Engine)
test-sdk:
	#!/usr/bin/env bash
	set -euo pipefail
	for suite in Exoforge.Client.Tests Exoforge.Plugin.SDK.Tests Exoforge.Plugin.Generator.Tests Exoforge.Management.Tests; do
		if [ "$suite" = "Exoforge.Client.Tests" ]; then
			# The vertical slice needs a live server; `test-e2e` owns it. Without this filter the recipe
			# failed whenever no server was running, under a name that says it does not need one.
			dotnet test "sdk/csharp/$suite" --filter "FullyQualifiedName!~VerticalSliceIntegrationTests"
		elif [ "$suite" = "Exoforge.Plugin.SDK.Tests" ]; then
			dotnet test "sdk/csharp/$suite" --filter "Category!=SlowIntegration"
		else
			dotnet test "sdk/csharp/$suite"
		fi
	done
	# A plugin's assembly is compiled to a process the server runs, so compiling the sample is the
	# check that the generator and the SDK still agree about what a plugin is.
	sample_proj="extensions_csharp/sample_plugin/sample_plugin.csproj"
	dotnet build "$sample_proj" -v q --nologo

# Run live end-to-end integration test (Client -> WS :4000 -> native plugin -> Event -> Client)
test-e2e: db-up build-extensions
	#!/usr/bin/env bash
	set -euo pipefail
	pkill -f beam.smp 2>/dev/null || true
	sleep 0.5
	# A throwaway database and temp data dir so accounts, tokens and scores never land in exoforge_prod.
	data_dir=$(mktemp -d)
	test_db="exoforge_test_$$_$RANDOM"
	SERVER_PID=""
	cleanup() {
		if [ -n "$SERVER_PID" ]; then
			pkill -P "$SERVER_PID" 2>/dev/null || true
			kill "$SERVER_PID" 2>/dev/null || true
		fi
		pkill -f beam.smp 2>/dev/null || true
		"{{just_executable()}}" _pg-drop-db "$test_db" 2>/dev/null || true
		rm -rf "$data_dir"
	}
	trap cleanup EXIT
	echo "Starting Exoforge backend on a disposable database ($test_db)..."
	"{{just_executable()}}" _pg-create-db "$test_db"
	DATABASE_URL="postgres://postgres:postgres@127.0.0.1:${PGPORT:-5432}/$test_db" EXOFORGE_DATA_DIR="$data_dir" mix run --no-halt &
	SERVER_PID=$!
	echo "Waiting for ports 4000 and 4001..."
	for i in $(seq 1 40); do
		if nc -z 127.0.0.1 4000 2>/dev/null && nc -z 127.0.0.1 4001 2>/dev/null; then break; fi
		sleep 0.2
	done
	echo "Running C# client E2E test against live backend..."
	EXOFORGE_REQUIRE_E2E=1 dotnet test sdk/csharp/Exoforge.Client.Tests
	echo "E2E vertical slice passed successfully!"

# Run cluster performance benchmark
benchmark:
	mix test test/cluster_benchmark_test.exs

# ---- Build & Release ----

# Build the sample extension. The native runner looks for the binary beside the manifest.
build-extensions:
	#!/usr/bin/env bash
	set -euo pipefail
	ext_dir="extensions_csharp/sample_plugin"
	rid=$(dotnet --info | awk '/RID:/ {print $2; exit}')
	dotnet publish "$ext_dir/sample_plugin.csproj" -c Release -r "$rid" -v q --nologo
	# Replaced, not overwritten: a server running the extension holds the binary open, and writing over a
	# busy file fails with "Text file busy".
	cp "$ext_dir/bin/Release/net10.0/$rid/publish/sample_plugin" "$ext_dir/sample_plugin.new"
	chmod +x "$ext_dir/sample_plugin.new"
	mv -f "$ext_dir/sample_plugin.new" "$ext_dir/sample_plugin"
	echo "[build-extensions] $ext_dir/sample_plugin"

# Run backend in production mode (foreground)
prod: db-up build-extensions
	DATABASE_URL="${DATABASE_URL:-postgres://postgres:postgres@127.0.0.1:5432/exoforge_prod}" \
	SECRET_KEY_BASE="${SECRET_KEY_BASE:-$(mix phx.gen.secret)}" \
	LIVEVIEW_SIGNING_SALT="${LIVEVIEW_SIGNING_SALT:-exoforge_local_prod_liveview_salt}" \
	MIX_ENV=prod mix run --no-halt

# Assemble standalone OTP production release
release: build-extensions
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
docker-build: build-extensions
	{{container_engine}} build --build-arg COMMIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "dev") -t exoforge:latest .

# Run full stack with PostgreSQL using Compose
compose-up: build-extensions
	{{compose_cmd}} up -d --build

# Follow Compose logs
compose-logs:
	{{compose_cmd}} logs -f

# Stop Compose services
compose-down:
	{{compose_cmd}} down

# Restart Compose stack
compose-restart: compose-down compose-up

# Ensure local PostgreSQL container is running and accepting connections
db-up:
	#!/usr/bin/env bash
	set -euo pipefail
	pg_port="${PGPORT:-5432}"
	pg_user="${PGUSER:-postgres}"
	if (command -v pg_isready >/dev/null 2>&1 && pg_isready -h 127.0.0.1 -p "$pg_port" -U "$pg_user" >/dev/null 2>&1) || \
	   (command -v "{{container_engine}}" >/dev/null 2>&1 && "{{container_engine}}" exec exoforge_postgres pg_isready -U postgres -d exoforge_prod >/dev/null 2>&1); then
		echo "[db-up] PostgreSQL is ready on 127.0.0.1:${pg_port}"
		exit 0
	fi
	if ! command -v docker >/dev/null 2>&1 && ! command -v podman >/dev/null 2>&1; then
		echo "Docker (https://docs.docker.com/get-docker/) or Podman (https://podman.io/docs/installation) is required to run local PostgreSQL." >&2
		exit 1
	fi
	echo "[db-up] Starting PostgreSQL container..."
	POSTGRES_PORT="${POSTGRES_PORT:-$pg_port}" {{compose_cmd}} up -d postgres
	for _ in $(seq 1 60); do
		if ("{{container_engine}}" exec exoforge_postgres pg_isready -U postgres -d exoforge_prod >/dev/null 2>&1) || \
		   (command -v pg_isready >/dev/null 2>&1 && pg_isready -h 127.0.0.1 -p "$pg_port" -U "$pg_user" >/dev/null 2>&1); then
			echo "[db-up] PostgreSQL is ready on 127.0.0.1:${pg_port}"
			exit 0
		fi
		sleep 0.5
	done
	echo "[db-up] Timed out waiting for PostgreSQL on 127.0.0.1:${pg_port}" >&2
	exit 1

# Stop local PostgreSQL container
db-down:
	{{compose_cmd}} stop postgres

# Start only local PostgreSQL container
postgres-up: db-up

# Stop local PostgreSQL container
postgres-down: db-down

_pg-exec sql:
	#!/usr/bin/env bash
	set -euo pipefail
	sql='{{sql}}'
	if command -v "{{container_engine}}" >/dev/null 2>&1 && "{{container_engine}}" exec exoforge_postgres pg_isready -U postgres -d postgres >/dev/null 2>&1; then
		"{{container_engine}}" exec exoforge_postgres psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c "$sql" >/dev/null
	else
		PGPASSWORD="${PGPASSWORD:-postgres}" psql -h "${PGHOST:-127.0.0.1}" -p "${PGPORT:-5432}" -U "${PGUSER:-postgres}" -d postgres -v ON_ERROR_STOP=1 -c "$sql" >/dev/null
	fi

_pg-create-db name:
	@"{{just_executable()}}" _pg-exec 'CREATE DATABASE "{{name}}"'

_pg-drop-db name:
	@"{{just_executable()}}" _pg-exec 'DROP DATABASE IF EXISTS "{{name}}" WITH (FORCE)'

# Deploy to Kubernetes cluster via Kustomize (with sensible defaults)
k8s-deploy:
	#!/usr/bin/env bash
	set -euo pipefail
	DATABASE_URL="${DATABASE_URL:-postgres://postgres:postgres@postgres:5432/exoforge_prod}"
	POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
	SECRET_KEY_BASE="${SECRET_KEY_BASE:-$(mix phx.gen.secret 2>/dev/null || echo exoforge_secret_key_base_min_64_characters_long_for_dev_mode_testing)}"
	LIVEVIEW_SIGNING_SALT="${LIVEVIEW_SIGNING_SALT:-exoforge_liveview_salt_for_studio_sockets_at_least_8}"
	RELEASE_COOKIE="${RELEASE_COOKIE:-exoforge_cluster_cookie}"
	EXOFORGE_ADMIN_PASSWORD="${EXOFORGE_ADMIN_PASSWORD:-admin12345}"
	kubectl create namespace exoforge --dry-run=client -o yaml | kubectl apply -f -
	kubectl -n exoforge create secret generic exoforge-secrets \
		--from-literal=DATABASE_URL="$DATABASE_URL" \
		--from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
		--from-literal=SECRET_KEY_BASE="$SECRET_KEY_BASE" \
		--from-literal=LIVEVIEW_SIGNING_SALT="$LIVEVIEW_SIGNING_SALT" \
		--from-literal=RELEASE_COOKIE="$RELEASE_COOKIE" \
		--from-literal=EXOFORGE_ADMIN_PASSWORD="$EXOFORGE_ADMIN_PASSWORD" \
		--dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -k deploy/k8s

# Teardown Kubernetes resources
k8s-destroy:
	kubectl delete -k deploy/k8s

# ---- Unity SDK Package ----

# Place the built package inside the sample, where Unity picks it up as an embedded package.
#
# The sample names no path outside itself - it is an example, and it has to open and run for someone
# who has this repository nowhere near them. So the package is copied in rather than referenced, and
# Packages/manifest.json lists only real registry packages.
unity-sync: build-unity-sdk
	#!/usr/bin/env bash
	set -euo pipefail
	dest="{{SAMPLE}}/Packages/com.exoforge.sdk"
	rm -rf "$dest"
	mkdir -p "$dest"
	cp -RL sdk/unity/Exoforge.SDK/. "$dest/"
	find "$dest" -type d \( -name bin -o -name obj \) -prune -exec rm -rf {} +
	echo "[unity-sync] package placed in {{SAMPLE}}/Packages/com.exoforge.sdk"

# Generate strongly-typed Unity C# client bindings (offline from workspace contracts or online from cluster)
gen-client:
	dotnet run --project sdk/csharp/Exoforge.CLI -- sync --dir sdk/unity/sample_unity/Exoforge


# Rebuild and re-place the package whenever the SDK changes. For editing the package or the C#
# libraries: nothing to remember to run, and Unity reimports on its own when the files change.
watch-unity:
	#!/usr/bin/env bash
	set -euo pipefail
	watched=(sdk/unity/Exoforge.SDK sdk/csharp/Exoforge.Client sdk/csharp/Exoforge.Management sdk/csharp/Exoforge.Plugin.SDK sdk/csharp/Exoforge.Plugin.Generator)
	# Polling rather than inotify: it costs a `find` a second, and needs nothing installed. `%T@` is
	# mtime to the nanosecond, so a rewrite that keeps the size still shows up.
	stamp() {
		find "${watched[@]}" -type f \
			\( -name '*.cs' -o -name '*.asmdef' -o -name '*.json' -o -name '*.csproj' -o -name '*.targets' \) \
			-not -path '*/bin/*' -not -path '*/obj/*' -printf '%T@ %p\n' 2>/dev/null | sort | md5sum
	}

	previously=$(stamp)
	just unity-sync
	echo "[watch-unity] watching the package and the C# libraries - ctrl-c to stop"

	while true; do
		sleep 1
		current=$(stamp)
		[ "$current" = "$previously" ] && continue
		previously=$current
		if just unity-sync >/dev/null; then
			echo "[watch-unity] rebuilt and placed at $(date +%T)"
		else
			echo "[watch-unity] build failed; still watching"
		fi
	done

# ---- Unity Sample (CLI-driven) ----
# The sample scene is built from code, not hand-edited YAML. Everything runs headless.
# The Unity editor, found rather than assumed. UNITY_PATH wins; otherwise the newest Hub install on
# either platform. The previous value was one hard-coded macOS path, which is wrong on every other
# machine and does not say so - `just sample-check` just failed.
UNITY := `if [ -n "${UNITY_PATH:-}" ]; then echo "$UNITY_PATH"; else found=$(ls -d "$HOME"/Unity/Hub/Editor/*/Editor/Unity "$HOME"/Unity/Hub/Editor/*/Unity.app/Contents/MacOS/Unity /Applications/Unity/Hub/Editor/*/Unity.app/Contents/MacOS/Unity /opt/unity/editors/*/Editor/Unity 2>/dev/null | tail -1); echo "${found:-$(command -v unity || echo unity)}"; fi`
SAMPLE := "sdk/unity/sample_unity"

# Private: stop Unity and clear its lockfile, so a batch run starts from a known state.
_unity-reset:
	#!/usr/bin/env bash
	# By the editor's own name: the bundle path above is macOS's, and Linux's is different.
	pkill -f "$(basename "{{UNITY}}")" 2>/dev/null || true
	sleep 1
	rm -f {{SAMPLE}}/Temp/UnityLockfile

# Rebuild the sample scene (idempotent)
sample-setup: unity-sync _unity-reset
	@{{UNITY}} -batchmode -quit -nographics -projectPath "$(pwd)/{{SAMPLE}}" -executeMethod ExoforgeSampleSetup.SetUp -logFile /tmp/exoforge-sample-setup.log; status=$?; grep -E "ExoforgeSample\]" /tmp/exoforge-sample-setup.log || true; exit $status

# Play mode, because Awake does not run in the editor — the session lifecycle is inert there.
# Run the sample's play-mode tests (session lifecycle)
sample-play-tests: unity-sync _unity-reset
	#!/usr/bin/env bash
	set -euo pipefail
	rm -f /tmp/exoforge-play-tests.xml
	"{{UNITY}}" -batchmode -nographics -projectPath "$(pwd)/{{SAMPLE}}" \
		-runTests -testPlatform PlayMode \
		-testResults /tmp/exoforge-play-tests.xml \
		-logFile /tmp/exoforge-play-tests.log
	python3 -c "import xml.etree.ElementTree as E; r=E.parse('/tmp/exoforge-play-tests.xml').getroot(); print('  tests=%s passed=%s failed=%s' % (r.get('testcasecount'), r.get('passed'), r.get('failed')))"

# Headless self-check for the sample (board pixel maths + leaderboard parsing)
sample-check: unity-sync _unity-reset
	@{{UNITY}} -batchmode -nographics -projectPath "$(pwd)/{{SAMPLE}}" -executeMethod ExoforgeSampleCheck.Run -logFile /tmp/exoforge-sample-check.log; status=$?; grep -E "ExoforgeSampleCheck\]" /tmp/exoforge-sample-check.log || true; exit $status

# ---- Unity SDK Package ----

# Starts the backend, deploys the sample plugin, runs the tests, stops the server again.
sample-live-tests: db-up unity-sync
	#!/usr/bin/env bash
	set -euo pipefail
	pkill -f "mix run" 2>/dev/null || true
	sleep 1

	# A throwaway database, so the accounts, scores and players these tests create never touch exoforge_prod.
	data_dir=$(mktemp -d)
	test_db="exoforge_test_$$_$RANDOM"
	server=""
	cleanup() {
		if [ -n "$server" ]; then
			kill "$server" 2>/dev/null || true
		fi
		pkill -f "mix run" 2>/dev/null || true
		pkill -f beam.smp 2>/dev/null || true
		"{{just_executable()}}" _pg-drop-db "$test_db" 2>/dev/null || true
		rm -rf "$data_dir"
	}
	# Kill the BEAM too, not just the wrapper: `kill` on `mix run` can leave it holding port 4000,
	# and then the offline play-mode tests run against a half-dead server instead of skipping.
	trap cleanup EXIT

	"{{just_executable()}}" _pg-create-db "$test_db"
	DATABASE_URL="postgres://postgres:postgres@127.0.0.1:${PGPORT:-5432}/$test_db" EXOFORGE_DATA_DIR="$data_dir" mix run --no-halt > /tmp/exoforge-live-tests-server.log 2>&1 &
	server=$!

	for _ in $(seq 1 60); do
		nc -z 127.0.0.1 4000 2>/dev/null && break
		sleep 0.5
	done

	echo "[sample-live-tests] deploying the sample extension"
	(cd {{SAMPLE}} && dotnet run --project ../../../sdk/csharp/Exoforge.CLI -- extension push snake_leaderboard >/dev/null)

	just sample-play-tests


# Build the engine-agnostic C# libraries into the Unity package as binaries.
#
# The client and the tooling are not Unity-specific, so they are not Unity's to own. Each engine SDK
# ships them as a compiled assembly, which keeps the package purely engine-specific and means the
# next engine (Unreal, Godot) reuses the same libraries rather than reimplementing them.
#
# A build step rather than committed binaries: a checked-in DLL is a copy that can silently go stale,
# which is the same failure a synced source file has. The package's own sources (Runtime/*.cs,
# Editor/*.cs) are the real thing - nothing outside the package compiles them, so there is no second
# copy of those to keep in step.
build-unity-sdk root=".":
	#!/usr/bin/env bash
	set -euo pipefail
	root="${1:-.}"
	out="$root/sdk/csharp"
	# One release per pack: the package's version is read from the Unity package's own manifest
	# (Directory.Build.props), and a leftover nupkg from an older version would travel beside it.
	rm -rf "$root/dist/nuget"
	mkdir -p "$root/dist/nuget"

	# Where each library lands is decided by the staging hook in Directory.Build.targets, by project
	# name, so this is only a build and the copies happen on the way past. Release, because the
	# package ships what a game runs.
	dotnet build "$out/Exoforge.Client" -c Release --nologo -v q
	dotnet build "$out/Exoforge.Management" -c Release --nologo -v q

	# Pack the Plugin SDK (which bundles Exoforge.Plugin.Generator as an analyzer)
	# into both dist/nuget (standalone bundle) and Editor/Plugins/NuGet~ (embedded in Unity SDK).
	# The package is versioned now, so an older .nupkg left here would ship beside the new one.
	rm -rf "$root/dist/nuget" "$root/sdk/unity/Exoforge.SDK/Editor/Plugins/NuGet~"
	dotnet pack "$out/Exoforge.Plugin.SDK" -c Release -o "$root/dist/nuget" --nologo -v q
	rm -rf "$root/sdk/unity/Exoforge.SDK/Editor/Plugins/Tools~"
	mkdir -p "$root/sdk/unity/Exoforge.SDK/Editor/Plugins/NuGet~"
	cp "$root/dist/nuget/"*.nupkg "$root/sdk/unity/Exoforge.SDK/Editor/Plugins/NuGet~/"

	# Publish the CLI into Editor/Cli~ for zero-dependency agent tooling inside Unity projects
	cli_proj="$out/Exoforge.CLI/Exoforge.CLI.csproj"
	[ -f "$cli_proj" ] || cli_proj="$out/Exoforge.Cli/Exoforge.CLI.csproj"
	rm -rf "$root/sdk/unity/Exoforge.SDK/Editor/Cli~"
	dotnet publish "$cli_proj" -c Release --no-self-contained -o "$root/sdk/unity/Exoforge.SDK/Editor/Cli~" --nologo -v q
	{
		echo '#!/usr/bin/env bash'
		echo 'set -euo pipefail'
		echo 'DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"'
		echo 'exec dotnet "$DIR/exo.dll" "$@"'
	} > "$root/sdk/unity/Exoforge.SDK/Editor/Cli~/exo"
	chmod +x "$root/sdk/unity/Exoforge.SDK/Editor/Cli~/exo"
	{
		echo '@echo off'
		echo 'dotnet "%~dp0exo.dll" %*'
	} > "$root/sdk/unity/Exoforge.SDK/Editor/Cli~/exo.cmd"

	echo "[build-unity-sdk] sdk/unity/Exoforge.SDK Runtime/Plugins + Editor/Plugins + NuGet~ + Cli~ staged"


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


# Force Unity to re-read the package (clears the import caches the editor builds up)
unity-reimport: unity-sync _unity-reset
	#!/usr/bin/env bash
	set -euo pipefail
	project=sdk/unity/sample_unity
	rm -rf "$project/Library/ScriptAssemblies" "$project/Library/Bee" \
	       "$project/Library/ArtifactDB" "$project/Library/ArtifactDB-lock" \
	       "$project/Library/SourceAssetDB" "$project/Library/SourceAssetDB-lock"
	echo "[unity-reimport] import caches cleared — Unity recompiles on next open"

# Slow — creates a Unity project and runs a framework-dependent publish — but it is the only check
# that tests what a consumer actually does. Build it here; run it in CI, not in the local loop.
clean-room-sdk:
	#!/usr/bin/env bash
	set -euo pipefail
	work=$(mktemp -d)
	# Keep the workspace on failure. The log is the only thing that says why the probe threw, and
	# deleting it with the directory turns every failure into an identical blind re-run.
	trap 'status=$?; if [ $status -eq 0 ]; then rm -rf "$work"; else echo "[clean-room] kept $work"; fi; exit $status' EXIT

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

# Integration test (run on demand): creates a clean temporary Unity project,
# imports the packaged SDK tarball (dist/com.exoforge.sdk-*.tgz), checks for compilation errors,
# writes any compile errors to log/unity-compilation-errors.log, and tests live auth/connection
# against localhost (or $EXOFORGE_TEST_URL).
test-unity-package: db-up
	#!/usr/bin/env bash
	set -euo pipefail

	started_server=0
	server_pid=""
	data_dir=""
	test_db=""
	cleanup() {
		if [ "$started_server" -eq 1 ] && [ -n "$server_pid" ]; then
			echo "[test-unity-package] Stopping temporary backend server..."
			kill "$server_pid" 2>/dev/null || true
			pkill -f "mix run" 2>/dev/null || true
			pkill -f beam.smp 2>/dev/null || true
		fi
		if [ -n "$test_db" ]; then
			"{{just_executable()}}" _pg-drop-db "$test_db" 2>/dev/null || true
		fi
		if [ -n "$data_dir" ] && [ -d "$data_dir" ]; then
			rm -rf "$data_dir"
		fi
	}
	trap cleanup EXIT

	target_url="${EXOFORGE_TEST_URL:-http://localhost:4001}"
	if [[ "$target_url" == *"localhost"* ]] || [[ "$target_url" == *"127.0.0.1"* ]]; then
		if ! nc -z 127.0.0.1 4000 2>/dev/null; then
			data_dir=$(mktemp -d)
			test_db="exoforge_test_$$_$RANDOM"
			echo "[test-unity-package] Starting local backend server with disposable database ($test_db)..."
			"{{just_executable()}}" _pg-create-db "$test_db"
			DATABASE_URL="postgres://postgres:postgres@127.0.0.1:${PGPORT:-5432}/$test_db" EXOFORGE_DATA_DIR="$data_dir" mix run --no-halt > /tmp/exoforge-package-test-server.log 2>&1 &
			server_pid=$!
			started_server=1

			for _ in $(seq 1 60); do
				nc -z 127.0.0.1 4000 2>/dev/null && break
				sleep 0.5
			done
		else
			echo "[test-unity-package] Using existing local cluster on port 4000"
		fi
	fi

	echo "[test-unity-package] 1/4 Packaging latest Exoforge Unity SDK..."
	just pack-unity >/dev/null
	tarball=$(ls -t dist/com.exoforge.sdk-*.tgz | head -1)
	abs_tarball="$(cd "$(dirname "$tarball")" && pwd)/$(basename "$tarball")"
	echo "[test-unity-package] Using package: $abs_tarball"

	mkdir -p log
	err_log="$(pwd)/log/unity-compilation-errors.log"
	test_log="$(pwd)/log/unity-package-test.log"
	rm -f "$err_log" "$test_log"

	work=$(mktemp -d -t exo-pkg-test-XXXXXX)
	echo "[test-unity-package] 2/4 Creating fresh Unity project at $work/Game..."
	if ! "{{UNITY}}" -batchmode -quit -nographics -createProject "$work/Game" -logFile "$work/create.log" >/dev/null; then
		cp "$work/create.log" "$err_log"
		echo "[test-unity-package] FAILED to create Unity project. Log saved to $err_log"
		exit 1
	fi

	echo "[test-unity-package] 3/4 Adding package tarball to manifest and staging probe..."
	python3 -c "import json, sys; p, t = sys.argv[1], sys.argv[2]; f = open(p, 'r'); d = json.load(f); f.close(); d.setdefault('dependencies', {})['com.exoforge.sdk'] = 'file:' + t; f = open(p, 'w'); json.dump(d, f, indent=2); f.close()" "$work/Game/Packages/manifest.json" "$abs_tarball"

	mkdir -p "$work/Game/Assets/Editor"
	cp sdk/unity/package-test-probe.cs "$work/Game/Assets/Editor/ExoforgePackageProbe.cs"

	echo "[test-unity-package] 4/4 Compiling project and executing probe..."
	set +e
	"{{UNITY}}" -batchmode -nographics \
		-projectPath "$work/Game" \
		-executeMethod ExoforgePackageProbe.Run \
		-logFile "$work/run.log"
	unity_status=$?
	set -e

	if [ $unity_status -ne 0 ]; then
		cp "$work/run.log" "$err_log"
		echo ""
		echo "================================================================================"
		echo "❌ [test-unity-package] Unity SDK package test FAILED (exit code: $unity_status)"
		echo "================================================================================"
		echo "Full log saved to: log/unity-compilation-errors.log"
		echo ""
		echo "Compilation & error lines:"
		grep -E "error CS|Compilation failed|Scripts have compiler errors|\[package-probe\] FAIL|Exception" "$err_log" | head -30 || true
		echo "================================================================================"
		echo "Temp project kept for inspection at: $work"
		exit $unity_status
	else
		cp "$work/run.log" "$test_log"
		echo ""
		echo "================================================================================"
		echo "✅ [test-unity-package] Unity SDK package test PASSED!"
		echo "================================================================================"
		grep -E "\[package-probe\]" "$test_log" | tail -15 || true
		echo "================================================================================"
		echo "Full log saved to: log/unity-package-test.log"
		rm -rf "$work"
	fi


# ---- Unity SDK Distribution ----

# Build the distributable Unity package: the UPM tarball, with the plugin SDK inside it so a
# developer with no repository and no published feed can build their first plugin.
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

	# The plugin SDK travels with the package. A developer has no repository and no published feed, so
	# without this their first `dotnet build` is NU1101 and nothing they can do fixes it.
	just pack-sdk >/dev/null
	mkdir -p "dist/package/Editor/Plugins/NuGet~"
	cp dist/nuget/*.nupkg "dist/package/Editor/Plugins/NuGet~/"
	# Build output in the package is not the package: Unity compiles what it is given, and a stale
	# bin/ or obj/ is the source of a whole class of "works on my machine".
	find dist/package -type d \( -name bin -o -name obj \) -prune -exec rm -rf {} +
	# COPYFILE_DISABLE: macOS otherwise writes ._ AppleDouble members into the archive, and Unity
	# imports them as package files.
	COPYFILE_DISABLE=1 tar -czf "dist/com.exoforge.sdk-${VERSION}.tgz" -C dist package
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

	# Unity ignores a file without a .meta in an immutable package - silently, so a type the code needs is
	# just "not found" (ExoProfile.cs in 0.1.49). Every source a project compiles must carry one.
	missing=$(cd dist/package && find Runtime Editor -name '*.cs' ! -path '*~*' | while read -r f; do [ -f "$f.meta" ] || echo "$f"; done)
	if [ -n "$missing" ]; then
		echo "[Exoforge] FAILED: these files have no .meta, so Unity would ignore them:"
		echo "$missing"
		exit 1
	fi

	just check-unity-package
	echo "Distributable: dist/com.exoforge.sdk-*.tgz"

# Verify that the packed Unity SDK tarball ships embedded AI agent tooling and CLI binaries.
check-unity-package:
	#!/usr/bin/env bash
	set -euo pipefail
	VERSION=$(grep '"version"' sdk/unity/Exoforge.SDK/package.json | head -1 | awk -F'"' '{print $4}')
	tarball="dist/com.exoforge.sdk-${VERSION}.tgz"
	if [ ! -f "$tarball" ]; then
		echo "[check-unity-package] FAILED: $tarball not found (run 'just pack-unity' first)"
		exit 1
	fi
	contents=$(tar -tzf "$tarball")
	required=(
		"package/Agents~/AGENTS.md"
		"package/Agents~/skills/exoforge-connection/SKILL.md"
		"package/Agents~/skills/exoforge-extensions/SKILL.md"
		"package/Agents~/skills/exoforge-resources/SKILL.md"
		"package/Editor/Cli~/exo"
		"package/Editor/Cli~/exo.cmd"
		"package/Editor/Cli~/exo.dll"
	)
	for entry in "${required[@]}"; do
		if ! grep -Fxq "$entry" <<< "$contents"; then
			echo "[check-unity-package] FAILED: missing '$entry' in $tarball"
			exit 1
		fi
	done
	echo "[check-unity-package] Verified Agents~ and Editor/Cli~ contents in $tarball"

