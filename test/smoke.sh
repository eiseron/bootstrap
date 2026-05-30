#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export BOOTSTRAP_TEMPLATE_BASE="$repo_root/templates"
# shellcheck source=../bootstrap.sh
source "$repo_root/bootstrap.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# app_name validation: accept OTP names, reject sed-unsafe / malformed input.
validate_app_name afinados || fail "valid app name rejected"
validate_app_name my_app2 || fail "valid app name rejected"
if validate_app_name "foo/bar"; then fail "name with slash accepted"; fi
if validate_app_name "1bad"; then fail "name with leading digit accepted"; fi
if validate_app_name "Bad"; then fail "name with uppercase accepted"; fi
if validate_app_name ""; then fail "empty name accepted"; fi

render_all afinados

# Every template rendered to its target path.
for f in compose.yml .gitlab-ci.yml .credo.exs .formatter.exs; do
  [ -f "$f" ] || fail "missing rendered file: $f"
done

# No .docker/ — generated projects reference the published dev image.
[ -e .docker ] && fail ".docker/ should not be generated"

# __APP_NAME__ fully substituted; no leftover placeholders anywhere.
for f in compose.yml .gitlab-ci.yml .credo.exs .formatter.exs; do
  grep -q "__APP_NAME__" "$f" && fail "unsubstituted placeholder in $f"
done
grep -q "app_name: afinados" .gitlab-ci.yml || fail "app name not substituted into .gitlab-ci.yml"

# compose is a remote OCI include of the shared Phoenix dev stack (no local
# services/build/image — those live in the versioned compose-phoenix artifact).
grep -q "oci://registry.gitlab.com/eiseron/stack/public-image-bases/compose-phoenix:v0.1.1" compose.yml \
  || fail "compose.yml does not include the compose-phoenix OCI artifact"
grep -q "project_directory: \\." compose.yml \
  || fail "include is missing project_directory: . (relative paths in the artifact would resolve to the OCI cache, not the project)"
grep -q "dockerfile:" compose.yml && fail "compose.yml should not build a local image"
grep -qE "^services:" compose.yml && fail "compose.yml should not define services locally"

# CI includes the shared stack/ci templates pinned to a tag.
grep -q "file: /templates/phoenix.yml" .gitlab-ci.yml || fail ".gitlab-ci.yml does not include phoenix.yml"
grep -q "file: /templates/sync-github.yml" .gitlab-ci.yml || fail ".gitlab-ci.yml does not include sync-github.yml"
grep -q "ref: v0.1.0" .gitlab-ci.yml || fail "stack/ci include is not pinned to a tag"
grep -q "app_name: afinados" .gitlab-ci.yml || fail "app_name not passed to phoenix.yml include"

# Dep injection against a realistic phx.new fixture.
cp "$repo_root/test/fixtures/mix.exs" mix.exs
inject_deps mix.exs

grep -q "eiseron_core" mix.exs || fail "eiseron_core not injected"
grep -q "eiseron_devtools" mix.exs || fail "eiseron_devtools not injected"

# Injected entries must precede the original first dep (so they carry the
# trailing comma and never strand the comma-less last dep).
core_line="$(grep -n "eiseron_core" mix.exs | head -1 | cut -d: -f1)"
phoenix_line="$(grep -n "{:phoenix," mix.exs | head -1 | cut -d: -f1)"
[ "$core_line" -lt "$phoenix_line" ] || fail "eiseron deps not injected at list head"

# Structural sanity: balanced brackets in the deps list region.
elixir_check() {
  command -v elixir >/dev/null 2>&1 || return 0
  elixir -e "Code.string_to_quoted!(File.read!(\"mix.exs\"))" || fail "mix.exs is not valid Elixir"
}
elixir_check

echo "smoke OK"
