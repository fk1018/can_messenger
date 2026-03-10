---
sidebar_position: 7
---

# Development (next)

These docs describe active development workflow after the `2.1.0` snapshot.

## Docker-first Workflow

From repository root:

```bash
docker compose run --rm docs npm ci
docker compose build app
docker compose run --rm lint
docker compose run --rm test
docker compose run --rm build
```

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
- `docs-site/versioned_docs/version-2.1.0/*` = stable snapshot for `2.1.0`.
- `docs-site/versions.json` controls available released versions.
