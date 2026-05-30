# bootstrap

Project generator for new Eiseron products. Generates a fresh Phoenix project
wired up with `:eiseron_core`, `:eiseron_devtools`, the Eiseron Credo config,
and a Docker Compose dev environment — ready for `mix precommit` to pass.

## Usage

```sh
curl -fsSL https://raw.githubusercontent.com/eiseron/bootstrap/v0.1.0/bootstrap.sh | bash -s -- <app_name>
```

Or clone and run locally:

```sh
./bootstrap.sh <app_name>
```

## What it generates

```
<app_name>/
  compose.yml             remote OCI include of the shared compose-phoenix stack
  mix.exs                 phx.new output + eiseron_core/eiseron_devtools deps
  .gitlab-ci.yml          includes eiseron/stack/ci /templates/phoenix.yml + sync-github
  .credo.exs              Eiseron Credo standard
  .formatter.exs          Phoenix formatter config
  ... (rest of mix phx.new output)
```

Both `compose.yml` and `.gitlab-ci.yml` are thin, tag-pinned references to
shared infra — no infrastructure is duplicated into the project:
- `compose.yml` → `include: [oci://…/public-image-bases/compose-phoenix:vX.Y.Z]`
  (the `app`+`postgres` dev stack, pulling the published `elixir-tools` image)
- `.gitlab-ci.yml` → `include:` of `eiseron/stack/ci` templates, pinned by tag

## How it works

Templates live in `templates/` as real, lintable files using an `__APP_NAME__`
placeholder. `bootstrap.sh` fetches each one (from the public mirror, pinned to
its own release tag via `BOOTSTRAP_REF`) and substitutes the app name, then runs
`mix phx.new` inside Docker Compose and injects `:eiseron_core` +
`:eiseron_devtools` at the head of the deps list.

`BOOTSTRAP_TEMPLATE_BASE` overrides where templates are read from — a URL or a
local directory. The CI smoke test points it at the local `templates/` dir so it
validates generation without network or a Docker daemon.

## Requirements

- `bash`, `curl`, `docker` (with the Compose plugin), `awk`, `sed`

## Development

`bootstrap.sh` is sourceable — its `render`/`inject_deps` functions run without
side effects when sourced. `test/smoke.sh` sources it and exercises template
rendering + dep injection against `test/fixtures/mix.exs`, no Docker required.
