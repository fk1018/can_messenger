# Repository Guidelines

## Project Structure & Module Organization
`lib/` contains the gem code. `lib/can_messenger.rb` loads the public API; `lib/can_messenger/messenger.rb` handles send/listen flow; `lib/can_messenger/adapter/` contains transports; `lib/can_messenger/constants.rb` defines CAN ID masks and flags; and `lib/can_messenger/dbc.rb` contains DBC parsing plus the `Message` and `Signal` models. Keep `sig/` aligned with public API changes. Specs mirror runtime paths under `spec/lib/...`. Docs live in `docs-site/`: `docs/` is the unreleased `next` set, `versioned_docs/` stores release snapshots, and `src/`/`static/` hold site assets.

## Build, Test, and Development Commands
- `bin/setup`: install Ruby gems locally.
- `bin/console`: open IRB with the gem loaded.
- `bundle exec rake`: run the default gate (`rubocop` + `test:rspec`).
- `bundle exec rake test:rspec`: run RSpec only.
- `bundle exec rubocop`: lint Ruby code.
- `bundle exec rake build`: build the gem into `pkg/`.
- `docker compose run --rm <service>`: use `app`, `lint`, `test`, or `build` for containerized dev tasks.
- `docker compose up docs`: serve docs at `http://localhost:3000`.
- `docker compose run --rm docs sh -lc "npm ci && npm run build"`: build the docs site.

## Coding Style & Naming Conventions
Target Ruby 4.0.1+. Use 2-space indentation, `# frozen_string_literal: true`, and double-quoted strings; `.rubocop.yml` enforces the string rules. Match file paths to constants, for example `lib/can_messenger/adapter/socketcan.rb` -> `CanMessenger::Adapter::Socketcan`. When public behavior changes, update docs, `sig/`, and `CHANGELOG.md` in the same patch.

## Testing Guidelines
RSpec and SimpleCov are configured in `spec/test_helper.rb`; coverage output goes to `coverage/`. Name tests `*_spec.rb` and mirror the library path. Add or update specs for CAN ID validation, frame packing/parsing, DBC encode/decode behavior, adapter behavior, and logged error paths. Run `bundle exec rake` before opening a PR; for docs-only changes, at least build the docs site.

## Commit & Pull Request Guidelines
History is mixed, so prefer short descriptive commit subjects such as `Update RBS initialize signature` or `Bump version to 1.2.1 and update changelog`. PRs should explain the behavior change, note any `README.md`, `CHANGELOG.md`, `sig/`, or docs updates, and list the commands you ran. Link issues when relevant, and include screenshots only for `docs-site` UI changes.

## Environment & Release Notes
SocketCAN support is Linux-specific and raw-socket access may require elevated privileges or group membership. Do not commit generated output such as `coverage/`, `pkg/`, or `node_modules/`. When cutting a release, update versioned docs and `CHANGELOG.md` together.
