---
sidebar_position: 7
---

# Development Notes (2.2.0)

This page captures the `2.2.0` release snapshot.

## Docker-first Workflow

From repository root:

```bash
docker compose run --rm docs npm ci
docker compose build app
docker compose run --rm lint
docker compose run --rm test
docker compose run --rm build
```

Ruby services automatically run `bundle check || bundle install` inside the container, so an existing `bundle_cache` volume stays valid after gem changes.

### Docs Site

```bash
# Run docs dev server
docker compose up docs

# Build static docs bundle
docker compose run --rm docs sh -lc "npm ci && npm run build"
```

Docs dev server is exposed at `http://localhost:3000`.

## Local Ruby Workflow (optional)

```bash
bin/setup
bundle exec rake test:rspec
bundle exec rubocop
```

## CI / Release Workflow Notes

- Ruby checks (`test` + `rubocop`) run from the Ruby workflow.
- Gem release workflow is manual (`workflow_dispatch`).
- Docs deploy workflow is manual (`workflow_dispatch`).

## Docs Versioning Model

- `docs-site/docs/*` = `next` (unreleased stream).
- `docs-site/versioned_docs/version-2.2.0/*` = stable snapshot for `2.2.0`.
- `docs-site/versioned_docs/version-2.1.0/*` = archived snapshot for `2.1.0`.
- `docs-site/versions.json` controls available released versions.
