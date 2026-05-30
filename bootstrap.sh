#!/usr/bin/env bash

BOOTSTRAP_REF="${BOOTSTRAP_REF:-v0.1.0}"
TEMPLATE_BASE="${BOOTSTRAP_TEMPLATE_BASE:-https://raw.githubusercontent.com/eiseron/bootstrap/${BOOTSTRAP_REF}/templates}"

usage() {
  echo "Usage: bootstrap.sh <app_name>" >&2
  return 1
}

validate_app_name() {
  printf '%s' "$1" | grep -qE '^[a-z][a-z0-9_]*$'
}

fetch_template() {
  if [ -d "$TEMPLATE_BASE" ]; then
    cat "$TEMPLATE_BASE/$1"
  else
    curl -fsSL "$TEMPLATE_BASE/$1"
  fi
}

render() {
  local template="$1" target="$2" app="$3"
  mkdir -p "$(dirname "$target")"
  fetch_template "$template" | sed "s/__APP_NAME__/${app}/g" > "$target"
}

inject_deps() {
  local mix_file="$1"
  awk '
    /defp deps do/ { in_deps = 1 }
    in_deps && /^[ \t]*\[$/ {
      print $0
      print "      {:eiseron_core, git: \"https://github.com/eiseron/core.git\", tag: \"v0.1.1\"},"
      print "      {:eiseron_devtools,"
      print "       git: \"https://github.com/eiseron/devtools.git\","
      print "       tag: \"v0.1.0\","
      print "       only: [:dev, :test],"
      print "       runtime: false},"
      in_deps = 0
      next
    }
    { print }
  ' "$mix_file" > "$mix_file.tmp" && mv "$mix_file.tmp" "$mix_file"
}

render_all() {
  local app="$1"
  render compose.yml compose.yml "$app"
  render gitlab-ci.yml .gitlab-ci.yml "$app"
  render credo.exs .credo.exs "$app"
  render formatter.exs .formatter.exs "$app"
}

main() {
  set -euo pipefail

  [ $# -lt 1 ] && usage
  local app_name="$1"

  if ! validate_app_name "$app_name"; then
    echo "Error: app_name must match ^[a-z][a-z0-9_]*\$ (OTP application name)." >&2
    exit 1
  fi

  if [ -d "$app_name" ]; then
    echo "Error: directory '$app_name' already exists." >&2
    exit 1
  fi

  mkdir "$app_name"
  cd "$app_name"

  echo "Rendering templates..."
  render_all "$app_name"

  echo "Generating Phoenix project..."
  docker compose run --rm app sh -c "mix archive.install --force hex phx_new && mix phx.new . --app $app_name --no-install"

  echo "Injecting eiseron dependencies into mix.exs..."
  inject_deps mix.exs

  echo "Fetching dependencies..."
  docker compose run --rm app mix deps.get

  echo ""
  echo "Done! Next steps:"
  echo "  1. cd $app_name"
  echo "  2. git init && git add -A && git commit -m 'chore: bootstrap'"
  echo "  3. git remote add origin git@gitlab.com:eiseron/<group>/$app_name.git"
  echo "  4. git push -u origin main"
  echo "  5. docker compose run --rm app mix ecto.setup"
  echo "  6. docker compose up"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
