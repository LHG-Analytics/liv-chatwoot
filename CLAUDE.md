# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Canonical guidelines

**Read [AGENTS.md](AGENTS.md) first.** It is the source of truth for build/test/lint commands, code style, styling rules (Tailwind-only), commit/PR conventions, translation rules, and the Enterprise overlay workflow. This file does not repeat that content — it covers the high-level architecture that AGENTS.md omits.

Quick reference (full detail in AGENTS.md):
- Setup: `bundle install && pnpm install`
- Dev: `pnpm dev` (runs `overmind start -f ./Procfile.dev` → Rails `backend`, Sidekiq `worker`, Vite `vite`)
- Ruby test (single line): `bundle exec rspec spec/path/to/file_spec.rb:LINE`
- JS/Vue test: `pnpm test` (Vitest) ; lint: `pnpm eslint` / `bundle exec rubocop -a`
- Ruby 3.4.4 (via rbenv), Node 24.x, pnpm 10.x

## Big-picture architecture

Chatwoot is a **Rails 7.1 + Vue 3 monolith** (an open-source customer support / omnichannel inbox). It is a single Rails app serving multiple distinct Vue single-page applications, backed by Postgres, Redis, and Sidekiq.

### Backend (Rails, `app/`)

Layered beyond standard MVC — understanding the non-obvious layers matters more than the controllers/models:

- **`controllers/api/`** — the main JSON API, versioned and namespaced by audience: `api/v1/accounts/` (agent dashboard, account-scoped), `api/v1/widget/` (live-chat widget), `api/v2/` (reports). Also `platform/` (super-admin provisioning), `public/` (help-center/portal), `super_admin/` (admin panel via Administrate).
- **`services/`** — core business logic lives here, not in controllers/models. Grouped by domain (`conversations/`, `contacts/`, `messages/`, channel integrations like `facebook/`, `whatsapp`, `instagram/`, `slack/`). When adding behavior, look for or create a service.
- **`builders/`** — multi-step object construction (e.g. building a message + attachments + conversation in one flow).
- **`listeners/` + `dispatchers/` + `lib/events/`** — an event/pub-sub system. Domain events are dispatched and listeners react (notifications, webhooks, automation, reporting). This is how side effects are decoupled from the request cycle.
- **`jobs/`** — Sidekiq background jobs (async work, integrations, scheduled tasks).
- **`finders/`** — encapsulate complex query/filter logic (e.g. conversation filtering).
- **`policies/`** — Pundit authorization.
- **`mailboxes/`** — inbound email processing (Action Mailbox); **`mailers/`** outbound.
- **`lib/`** — cross-cutting infrastructure: `integrations/` (third-party channels), `captain/` + `llm/` (the AI agent "Captain"), `redis/`, `global_config*` (runtime config from DB), `seeders/`.

### Frontend (`app/javascript/`)

Multiple independent Vue 3 apps, each its own entrypoint (see `entrypoints/`):
- **`dashboard/`** — the main agent app (largest). Uses **Vuex** (`dashboard/store/`) for legacy state and **Pinia** for newer state. Note `components/` (legacy, being deprecated) vs **`components-next/`** (preferred for new message-bubble/UI work — see AGENTS.md).
- **`widget/`** — the embeddable live-chat widget loaded on customer sites.
- **`sdk/`** — the JS SDK that bootstraps the widget (`build:sdk` → `vite.lib.config.ts`, size-limited to 40KB).
- **`portal/`** — public help-center.
- **`v3/`**, **`survey/`**, **`superadmin_pages/`**, **`design-system/`** — smaller standalone apps.
- **`shared/`** — code shared across apps (incl. `composables/useBranding` for white-labeling).

Build is **Vite** (`vite.config.ts`, vite-plugin-ruby). Components use Composition API with `<script setup>`. Styling is **Tailwind only**.

### Enterprise overlay (`enterprise/`)

`enterprise/` mirrors the `app/` and `lib/` tree and **extends/overrides OSS code** via `prepend_mod_with` / `include_mod_with` rather than editing OSS files. **Any change to core logic, services, policies, controllers, or public API contracts must be checked against `enterprise/` for a corresponding override**, and Enterprise specs go under `spec/enterprise/`. This is the single most important architectural constraint when editing core code — see the detailed checklist in AGENTS.md.

### Data & async

Postgres (primary), Redis (cache, Action Cable, Sidekiq queues), Sidekiq (`config/sidekiq.yml`), Action Cable for real-time updates to the dashboard/widget.

## Where things live (when in doubt)

- New API endpoint → `controllers/api/v1/...` + route in `config/routes.rb` + matching `policies/` + (likely) a `services/` object.
- New business logic → `services/<domain>/`, not the controller.
- Side effect on a domain event → add a listener under `listeners/` driven by `lib/events/`.
- New background work → `jobs/`.
- Frontend feature → the relevant app under `app/javascript/`; prefer `components-next/` for dashboard UI.
- Always grep both trees: `rg -n "SomeService|SomeModel" app enterprise`.
