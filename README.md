# AegisZero — Zero-Trust Identity & Access Management Platform

An enterprise-style Zero-Trust IAM platform built as Spring Boot microservices: adaptive authentication, MFA, device and session intelligence, RBAC, event-driven risk scoring, and immutable audit logging — fronted by a Next.js security console.

See [architecture.md](architecture.md) and [development.md](development.md) for the full design and phased build plan this implementation follows, and [deployment.md](deployment.md) to put it on Render.

## Repo structure

Four top-level concerns each live in their own repo and are pulled into this one as [git submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules): [aegiszero-services](https://github.com/ChamathDilshanC/aegiszero-services), [aegiszero-shared](https://github.com/ChamathDilshanC/aegiszero-shared), [aegiszero-frontend](https://github.com/ChamathDilshanC/aegiszero-frontend), and [aegiszero-infrastructure](https://github.com/ChamathDilshanC/aegiszero-infrastructure). `docker-compose.yml`, `render.yaml`, and the root Maven reactor `pom.xml` live directly in this repo.

```bash
git clone --recurse-submodules https://github.com/ChamathDilshanC/AegisZero.git
# or, if already cloned without that flag:
git submodule update --init --recursive
```

The root `pom.xml`'s `<modules>` list expects each service checked out at its usual path (`services/auth-service`, `shared/common-events`, ...) — `mvn package` from the repo root won't find any service source until submodules are initialized.

## What's implemented

| Service | Port | Responsibility |
|---|---|---|
| `api-gateway` | 8080 | Spring Cloud Gateway: routing, edge JWT check, per-IP rate limiting, CORS, correlation IDs |
| `auth-service` | 8081 | Registration, login, JWT/refresh tokens, password reset, email verification, account lockout |
| `user-service` | 8082 | User profiles (created from `auth-service` via Kafka) |
| `access-service` | 8083 | RBAC: roles, permissions, role assignment, authorization lookups |
| `security-service` | 8084 | Risk scoring, device intelligence, Redis-backed sessions, MFA (TOTP + email OTP + recovery codes) |
| `audit-service` | 8085 | Consumes `audit.events`, immutable log storage, search + CSV export |
| `notification-service` | 8086 | Consumes `notification.events`, sends email via SMTP or the Brevo REST API (see below) |
| `frontend/security-console` | 3000 | Next.js dashboard: auth flows, sessions, devices, MFA settings, admin views |

All 7 services live in `services/` (one repo, `aegiszero-services`) and share one Maven reactor. `shared/` (`aegiszero-shared`) holds `common-exceptions`, `common-events`, `common-messaging`, and `common-security` — the JWT service, the event contracts and topic names, the backend-agnostic publish/subscribe layer over them (Kafka or Redis Streams), and a common exception/error-response shape used by every service.

### End-to-end flow that actually works today

Register → verify email → login → risk evaluation (new device / blocked IP) → MFA challenge if required → JWT + refresh token issued → call protected APIs through the gateway → view sessions/devices → revoke a session → that session's refresh tokens are invalidated via a Kafka event, closing the loop.

### Deliberate scope cuts (documented, not accidental)

- **Risk engine**: implements new-device and blocked-IP scoring. New-country / impossible-travel scoring is omitted (needs a GeoIP database); repeated-failed-login scoring is omitted here since `auth-service` already handles account lockout itself.
- **Sessions**: single-instance in-memory MFA challenge store in `auth-service`; a horizontally-scaled deployment would move this into Redis alongside session state.
- **Not built**: OAuth2/OIDC provider mode, WebAuthn/passkeys, multi-tenancy, API key management, Prometheus/Grafana wiring, Kubernetes manifests. `architecture.md`/`development.md` describe these as later phases.

## Quick start

Requires Docker Desktop and ~4GB free RAM for the full stack.

```bash
cp .env.example .env    # adjust JWT_SECRET etc. if you want
docker compose up -d --build
```

First boot takes a few minutes (Maven build inside the image + Flyway migrations). Once every service reports healthy:

- Security console: http://localhost:3000
- API Gateway: http://localhost:8080
- Kafka UI: http://localhost:8091
- Mailhog (catches all outgoing email): http://localhost:8026

Register an account in the console, then open Mailhog to grab the verification link (no real SMTP is configured in dev).

### Sending real email

`notification-service` has two ways to actually deliver mail, picked by `EMAIL_PROVIDER` (`smtp` by default):

- **`smtp`** — `JavaMailSender`, unchanged. Defaults to the bundled Mailhog container locally (nothing leaves your machine). For real SMTP delivery — anywhere outbound SMTP isn't blocked — point it at a relay instead by setting `SMTP_HOST`/`SMTP_PORT`/`SMTP_AUTH`/`SMTP_STARTTLS`/`SMTP_USERNAME`/`SMTP_PASSWORD`/`MAIL_FROM` in `.env`. Brevo's free SMTP works well for this (see `.env.example`).
- **`brevo-api`** — calls Brevo's transactional email REST API over HTTPS instead of opening an SMTP connection. This is the one that actually works on **Render's free tier**, which blocks outbound SMTP ports (25/465/587) entirely — `render.yaml` already sets `EMAIL_PROVIDER=brevo-api` for `notification-service`. Needs `BREVO_API_KEY` (an *API key*, not an SMTP key — different credential, same Brevo account), `MAIL_FROM`, and `MAIL_FROM_NAME`.

| Mode | `EMAIL_PROVIDER` | Where it's used |
|---|---|---|
| A. Local dev | `smtp` | `docker compose up` → Mailhog |
| B. SMTP deployment | `smtp` | Any host that allows outbound SMTP → Brevo SMTP or another relay |
| C. Render Free | `brevo-api` | Render (SMTP ports blocked) → Brevo REST API |

Never commit real SMTP or Brevo credentials — `.env` is gitignored, and `render.yaml` marks both as `sync: false` (set them in Render's dashboard directly).

### Running a single service locally (outside Docker)

```bash
docker compose up -d postgres redis kafka   # infra only
cd services/auth-service
mvn spring-boot:run
```

Each service's `application.yml` defaults to `localhost` for Postgres/Redis/Kafka and reads overrides from environment variables (see that file for the full list).

### Host port collisions

If you already have Postgres/Redis/Kafka/Mailhog running locally, `docker-compose.yml` publishes them on non-default host ports (`5434`, `6380`, `9095`, `8091`, `8026`, `1026`) specifically to avoid clashing — see `.env.example`. Containers still talk to each other over the internal Docker network on the standard ports.

## Repository layout

```
shared/            submodule (aegiszero-shared): common-exceptions, common-events, common-messaging, common-security
services/          submodule (aegiszero-services): the 7 Spring Boot services above, one Maven reactor
frontend/          submodule (aegiszero-frontend): security-console, the Next.js app
infrastructure/    submodule (aegiszero-infrastructure): Postgres multi-DB init script
docker-compose.yml  full local stack
render.yaml         Render Blueprint for a cloud deployment — see below
deployment.md       step-by-step Render deployment guide
Dockerfile          shared multi-stage build for every Java service (docker build --build-arg SERVICE_NAME=...)
```

The root `pom.xml` still treats `shared/*` and `services/*` as one Maven reactor — see "Repo structure" above for why `git submodule update --init --recursive` has to run before anything under those paths exists on disk.

### Working on the services or frontend

Each submodule is a normal git repo — commit and push inside it, then update the pointer here:

```bash
cd services   # or shared, frontend, infrastructure
git add -A && git commit -m "..." && git push
cd ..
git add services && git commit -m "chore: bump services submodule"
```

## Deploying to Render

**[deployment.md](deployment.md) is the step-by-step guide** — start there if you are actually deploying. What follows is the summary of what you are getting into.

`render.yaml` at the repo root is a [Render Blueprint](https://render.com/docs/blueprint-spec) covering Postgres, Redis, all 7 Java services, and the frontend — every service on Render's **free** plan. In the Render dashboard: **New → Blueprint**, point it at this repo (Render follows the submodules automatically since they're all public).

Read the comment block at the top of `render.yaml` first. Things worth knowing going in:

- **Every backend service is public, not private.** Render's free plan has no Private Service offering at all (Blueprint creation fails outright if you try `pserv`), so auth-service, user-service, access-service, security-service, audit-service, and notification-service all get their own `*.onrender.com` URL — not just the gateway and frontend. `access-service`'s and `security-service`'s `/internal/**` endpoints, previously open on the assumption that only trusted internal callers could reach them, now require a shared `X-Internal-Api-Key` header (`INTERNAL_API_KEY`, auto-generated by Render) that only `auth-service` sends.
- **There is no Kafka on Render — domain events ride Redis Streams instead.** Render has no managed Kafka at any plan, self-hosting a broker doesn't work (`type: web` health-checks for an HTTP response, which a broker never gives, and the free plan has no background workers), and Upstash Kafka — which an earlier version of `render.yaml` pointed at — [was deprecated in September 2024 and shut down on 11 March 2025](https://upstash.com/blog/workflow-kafka). So `render.yaml` sets `EVENT_BACKEND=redis` and events go over the free Redis already provisioned for sessions.

  Redis Streams consumer groups give the same two properties the design actually depends on: fan-out to independent consumers (user-service and access-service each see every `user.registered` event) and per-consumer offsets (a service that Render spun down picks up what it missed when it wakes). Streams are capped with `XADD MAXLEN ~` — `aegiszero.events.redis.max-stream-length`, default 1000 — so `audit.events` can't fill a 25MB Redis.

  No service code differs between the two. Publishers depend on `EventPublisher`, consumers implement `EventSubscription`, and `shared/common-messaging` wires whichever backend `aegiszero.events.backend` names. Local `docker compose up` leaves `EVENT_BACKEND` unset, which means Kafka against the bundled broker — genuinely unchanged.
- **One Postgres database, one schema per service.** Locally each service gets its own database (`auth_db`, `user_db`, ...) created by `infrastructure/postgres/init-databases.sh`. Render's free Postgres plan can't reproduce that: it gives you a single database, `databaseName` is fixed at creation time, and the user it hands you has no `CREATEDB` right — so the other four can be neither declared in `render.yaml` nor created afterwards by hand. Instead every service reads the real database name off the instance (`fromDatabase: property: database`, rather than assuming) and owns a schema inside it — `auth`, `users`, `access`, `security`, `audit` — via `DB_SCHEMA`. Flyway creates the schema on first run and keeps its own `flyway_schema_history` there, so the services stay as isolated as they were with a database each. No manual step, and local `docker compose up` is untouched: `DB_SCHEMA` is unset there, which means `public` inside a per-service database exactly as before.
- **Two env vars Render can't fill in for you**, both `sync: false` in `render.yaml` and both required by `notification-service` — it fails fast on startup without them: `BREVO_API_KEY` and `MAIL_FROM` (a sender address Brevo has verified). Set them on the service in the Render dashboard.
- **Free tier means cold starts**: every service spins down after ~15 min idle. A login can chain through 4 sleeping services, so the first request after a quiet period can take a couple of minutes — wake the demo up before showing it to anyone. JVM heaps are also capped tight (~300MB) to fit the 512MB free containers. None of this is a production setup — it's tuned to cost nothing for a portfolio demo.

## Tech stack

Java 21, Spring Boot 3.5, Spring Cloud Gateway 2025.0, Spring Security, Spring Data JPA + Flyway, Spring Kafka, Spring Data Redis, PostgreSQL 16, Redis 7, Apache Kafka (KRaft) — with Redis Streams as an interchangeable event backend for hosts without a broker — Next.js 16 + TypeScript + Tailwind CSS 4.
