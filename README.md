# FoodPOS

Offline-first restaurant Point-of-Sale for Indian F&B outlets (dine-in,
takeaway, delivery), with a SaaS control plane. Flutter terminals talk to a
Go backend over REST + SSE, keep taking orders through outages (outbox sync),
and reconcile shifts when they reconnect.

| Workspace | Stack | What it is |
|-----------|-------|------------|
| `lib/` (Flutter app) | Flutter + Provider | POS terminal: billing, KOT/KDS, shifts & cash drawer, inventory, reports |
| `backend/` | Go + PostgreSQL | REST API, SaaS tenancy/billing (plans, trials, Razorpay), embedded landing + console |
| `landing/` | React + Vite | Marketing site, pricing → signup, owner/superadmin console at `/console` |

## Quick start

```bash
# 1. Database (Docker)
docker compose up -d postgres

# 2. Backend — http://localhost:8080
cd backend
FOODPOS_DSN=postgres://foodpos:foodpos@localhost:5432/foodpos?sslmode=disable \
  go run ./cmd/server

# 3. Landing/console during development
cd landing && npm install && npm run dev

# 4. POS terminal against the local backend
flutter run --dart-define=FOODPOS_API_URL=http://localhost:8080
```

Demo data (`FOODPOS_SEED=1` on the server) logs in with PIN `1234` (cashier),
`9999` (manager), `0000` (admin) at org code `SPICE-HAVEN`.

## Verified commands

- backend: `cd backend && go vet ./... && go test ./... && go build ./...`
  (integration tests use `foodpos_test` on localhost:5432 — `docker compose up -d postgres`)
- flutter: `flutter analyze && flutter test`
- landing: `cd landing && npm ci && npm run build`
- release build of the Go binary with the embedded site: `cd backend && make run`
  (copies `../landing/dist` into `internal/web/webroot/`)

## Configuration

Backend env vars (see `backend/internal/config/config.go`):

- `FOODPOS_ENV=production` — enables secure defaults: `FOODPOS_JWT_SECRET`
  becomes mandatory and wildcard CORS is dropped (same-origin reverse proxy).
- `FOODPOS_JWT_SECRET`, `FOODPOS_DSN`, `FOODPOS_PORT`
- `FOODPOS_SEED=1` — load demo tenant/menu data
- `FOODPOS_DEV=1` — dev conveniences (e.g. echoing password-reset tokens when
  SMTP is off). Never enable in production.
- `FOODPOS_SMTP_*`, `FOODPOS_RAZORPAY_*`, `FOODPOS_LICENSE_SECRET`
- `FOODPOS_APP_BASE_URL`, `FOODPOS_CORS_ORIGINS`

Landing build: `VITE_FOODPOS_API_URL` (API base) and `VITE_FOODPOS_WHATSAPP`
(sales WhatsApp line).

## Docs

- `docs/PRD.md` — product requirements; `docs/ARCHITECTURE.md` — schema & API
- `memory/PROJECT_STATE.md` — current project state (agents: read this first)
- `docs/agents.md` — the agentic development protocol for this repo
