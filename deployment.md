# Deploying AegisZero to Render

Step-by-step for a clean deployment on Render's **free** plan, using the
`render.yaml` Blueprint at the repo root.

Everything here assumes a fresh start: no existing `aegiszero-*` services in
your Render account. If you have some left over from an earlier attempt, do
[Step 0](#step-0-remove-leftovers-from-a-previous-attempt) first — reusing a
half-configured Postgres instance is the single most common way this deploy
fails.

---

## What the Blueprint creates

10 resources, all on the free plan:

| Resource | Type | Notes |
|---|---|---|
| `aegiszero-postgres` | Postgres | one database, `aegiszero` |
| `aegiszero-redis` | Key Value (Valkey) | sessions, rate limiting, **and the event bus** |
| `aegiszero-auth-service` | Web | credentials, JWT issuance |
| `aegiszero-user-service` | Web | user profiles |
| `aegiszero-access-service` | Web | RBAC |
| `aegiszero-security-service` | Web | risk, MFA, devices, sessions |
| `aegiszero-audit-service` | Web | audit log |
| `aegiszero-notification-service` | Web | transactional email |
| `aegiszero-gateway` | Web | public API entry point |
| `aegiszero-frontend` | Web | Next.js console |

Two things that are **not** created, because the free plan cannot host them,
and which the code already works around:

- **No Kafka.** Render has no managed Kafka, cannot self-host one (a `type: web`
  health check expects an HTTP response, which a broker never gives, and the
  free plan has no background workers), and Upstash Kafka shut down in March
  2025. The Blueprint sets `EVENT_BACKEND=redis`, so domain events travel over
  Redis Streams instead. Consumer groups give the same fan-out and per-consumer
  offsets, so behaviour is unchanged. See `shared/common-messaging`.
- **No five databases.** The free Postgres plan gives you one database and a
  user with no `CREATEDB` right. Each service instead owns a *schema* inside the
  single database — `auth`, `users`, `access`, `security`, `audit` — created
  automatically by Flyway on first run. **You do not need to run any SQL by
  hand.** (Local `docker compose up` still uses a database per service; the
  difference is just the `DB_SCHEMA` variable being set.)
- **No private networking between services.** A free web service can send
  private-network requests but cannot receive them, so the gateway cannot
  reach any backend service by an internal hostname — there is no such
  address to reach. Every downstream call goes over the backend's public
  `onrender.com` URL instead, which is why Step 2 asks for seven of them by
  hand. This is the single most common way the deploy breaks after the
  services first come up — see Step 2 and the `UnknownHostException` entry
  in Troubleshooting before assuming it's something else.

---

## Before you start

1. **A Render account** — <https://dashboard.render.com>. The free plan needs no
   card.
2. **A Brevo account** — <https://www.brevo.com>, free tier is ~300 emails/day.
   You need two things from it:
   - An **API key** (not an SMTP key — different credential, same account):
     *Settings → SMTP & API → API keys → Generate a new API key*.
   - A **verified sender address**: *Senders, Domains & Dedicated IPs →
     Senders → Add a sender*, then click the confirmation email. Brevo rejects
     sends from unverified addresses, so this step is not optional.

   Brevo is used over its REST API rather than SMTP because Render's free tier
   blocks outbound SMTP ports (25/465/587) entirely.
3. **The repos must be public**, or Render cannot follow the submodules.
   `services`, `shared`, `frontend` and `infrastructure` are all pulled in as
   git submodules and Render clones them recursively.

---

## Step 0: remove leftovers from a previous attempt

Skip if this is your first deploy.

Render does **not** delete services when you remove them from `render.yaml`, and
it will not reconfigure a Postgres instance that already exists. Both cause
confusing failures, so clear them out:

1. Dashboard → for every existing `aegiszero-*` service: **⋯ → Delete**.
2. Delete the old `aegiszero-postgres` and `aegiszero-redis` too. This matters:
   `databaseName` is fixed when a Postgres instance is created and can never be
   changed, so an instance from an earlier attempt keeps its old database name
   and every service fails with `database "..." does not exist`.
3. Dashboard → **Blueprints** → delete the old Blueprint.

Confirm the dashboard shows no `aegiszero-*` resources before continuing.

---

## Step 1: create the Blueprint

1. Dashboard → **New → Blueprint**.
2. Connect your GitHub account if you have not already, and pick
   **`ChamathDilshanC/AegisZero`**.
3. Branch: **`main`**. Render finds `render.yaml` at the repo root on its own.
4. Give the Blueprint a name (`aegiszero` is fine) and click **Apply**.

Render now reads `render.yaml` and shows you what it will create, including a
prompt for the values it cannot generate itself — that is Step 2.

> If Apply fails with a validation error, the message names the offending key.
> Do not start editing services by hand in the dashboard; fix `render.yaml`,
> push, and re-sync. The dashboard and the Blueprint will otherwise disagree
> and the next sync will overwrite your edit.

---

## Step 2: supply the values Render cannot derive

Everything else is either a literal in `render.yaml`, generated by Render
(`JWT_SECRET`, `INTERNAL_API_KEY`), or wired from another resource (`DB_HOST`,
`REDIS_URL`, …). 12 values are marked `sync: false`, meaning Render asks you
for them and — importantly — never overwrites them on a later sync:

| Variable | Where | Value |
|---|---|---|
| `BREVO_API_KEY` | `aegiszero-notification-service` | the API key from Brevo |
| `MAIL_FROM` | `aegiszero-notification-service` | your **verified** sender address |
| `NEXT_PUBLIC_API_BASE_URL` | `aegiszero-frontend` | the gateway's real public URL |
| `CORS_ALLOWED_ORIGINS` | `aegiszero-gateway` | the console's real public URL |
| `FRONTEND_BASE_URL` | `aegiszero-notification-service` | the console's real public URL |
| `AUTH_SERVICE_URL` | `aegiszero-gateway` | auth-service's real public URL |
| `USER_SERVICE_URL` | `aegiszero-gateway` | user-service's real public URL |
| `ACCESS_SERVICE_URL` | `aegiszero-gateway` | access-service's real public URL |
| `SECURITY_SERVICE_URL` | `aegiszero-gateway` | security-service's real public URL |
| `AUDIT_SERVICE_URL` | `aegiszero-gateway` | audit-service's real public URL |
| `ACCESS_SERVICE_URL` | `aegiszero-auth-service` | access-service's real public URL |
| `SECURITY_SERVICE_URL` | `aegiszero-auth-service` | security-service's real public URL |

**Why the last seven exist at all — read this once, it explains most of what
goes wrong in Step 3.** It would be natural to assume the gateway reaches each
backend over Render's private network, the way `docker-compose` reaches
containers by name. It cannot. Render's own docs are explicit: *"Free web
services can send private network requests, but they can't receive them."*
Every one of these seven services is a free `type: web` service, so none of
them has a private-network address to receive on at all — not a permissions
issue, not a naming issue, there is simply no such address. Pointing at one
by any hostname fails with `UnknownHostException` / `NXDOMAIN`, correctly
spelled or not. The only thing that reaches a free web service from another
Render service is its public `onrender.com` URL, which is what every one of
these variables holds. `access-service`'s and `security-service`'s
`/internal/**` endpoints being reachable from the open internet as a result
is why they're guarded by `INTERNAL_API_KEY` rather than by network
isolation — see the note near the top of `render.yaml`.

**Get every one of these from the dashboard, after the services exist.**
Render appends a suffix when a service name is already taken, so you may well
end up with `aegiszero-gateway-y415.onrender.com` rather than the plain name.
Copy the real URLs rather than assuming — this is the single most common
mistake in this whole deploy.

All 12 are a chicken-and-egg problem on a first deploy: the services do not
exist yet during Apply, so their URLs are not known. Put anything in to get
past Apply, then come back once Step 3 finishes and every service has a real
URL, and set all 12 for real. **A code push alone will not apply a variable
you add or change afterwards on a service that already exists** — after
setting these, either the next push naturally redeploys the affected service,
or trigger it yourself with *Manual Deploy → Deploy latest commit* (or *Clear
build cache & deploy* for `NEXT_PUBLIC_API_BASE_URL`, since that one is
inlined into the JS bundle at build time — a plain restart changes nothing).

`notification-service` deliberately refuses to start without `BREVO_API_KEY` —
it fails fast with a clear message rather than silently dropping every
verification email. So if that one service is red and the rest are green, this
is why.

---

## Step 3: wait out the first build

The first deploy is slow. Each Java service builds inside Docker with
`mvn -pl <service> -am package`, so expect **5–10 minutes per service** and
possibly some queuing on the free plan. Budget 30–45 minutes for everything to
settle.

**Crash loops during this window are expected and self-correcting.** The
services come up before Postgres and Redis are ready, fail, and Render restarts
them. What you should see, in order:

1. `aegiszero-postgres` and `aegiszero-redis` → **Available**.
2. Backend services → a few `Exited with status 1` cycles, then **Live**.
   The first one to reach Flyway creates its schema; the rest follow.
3. `aegiszero-gateway` and `aegiszero-frontend` → **Live**.

One log line is worth recognising because it is misleading:

```
==> Port scan timeout reached, no open ports detected.
```

This is **not** the root cause. It means the container never bound a port
within Render's detection window, which happens because the app crashed on
startup. Scroll **up** past it to the actual exception.

---

## Step 4: check all 12 public URLs line up

If you filled in all 12 variables from Step 2 with the real dashboard URLs
already, this is a verification pass — go through the table again and confirm
each one still matches. If you put in placeholders to get past Apply, do it
for real now: every service in that table exists at this point and has a
real `onrender.com` URL to copy.

**`NEXT_PUBLIC_API_BASE_URL` is inlined into the JavaScript bundle at build
time**, so changing it requires a full rebuild — *Manual Deploy → Clear build
cache & deploy*, not a restart. A restart will appear to do nothing. Every
other variable in the table takes effect on the next deploy of that service —
trigger one with *Manual Deploy → Deploy latest commit* if nothing else is
about to redeploy it for you.

> **Why these are `sync: false` rather than declared values.** Anything given a
> `value:` in `render.yaml` is owned by the blueprint, and **every sync
> overwrites whatever is in the dashboard**. Correcting such a variable by hand
> works right up until the next sync silently puts the wrong value back — which
> presents as the console suddenly calling a hostname that does not exist, long
> after you thought it was fixed. Values Render cannot derive are declared
> `sync: false` so they are prompted once and then left alone.

### Symptoms of each one being wrong

- `AUTH_SERVICE_URL` / `USER_SERVICE_URL` / `ACCESS_SERVICE_URL` /
  `SECURITY_SERVICE_URL` / `AUDIT_SERVICE_URL` on the gateway, or
  `ACCESS_SERVICE_URL` / `SECURITY_SERVICE_URL` on auth-service, missing,
  blank, or pointing at the internal `aegiszero-x-service` name rather than
  a real `onrender.com` URL → every request through the gateway (or through
  auth-service to access/security) fails with a fast `500`. The gateway's
  own log names the exact cause: `UnknownHostException: Failed to resolve
  'aegiszero-x-service' ... NXDOMAIN`. See the note in Step 2 — there is no
  private hostname that works here at all, on any free web service.
- `NEXT_PUBLIC_API_BASE_URL` blank → every API call becomes a same-origin
  relative URL, hits the console itself, and returns the console's own 404.
- `NEXT_PUBLIC_API_BASE_URL` pointing at a host that does not exist → the
  browser reports a CORS failure, because a DNS or connection error on a
  cross-origin request surfaces as one.
- `CORS_ALLOWED_ORIGINS` not matching the console's origin → the request
  reaches the gateway and is refused at the preflight. `curl` will succeed
  against the same endpoint, which is the giveaway: curl does not send an
  `Origin` header.

---

## Step 5: verify it actually works

**Health checks.** Every backend service exposes `/actuator/health`. The
gateway is the one that matters most, since it proves Redis is reachable:

```bash
curl https://aegiszero-gateway.onrender.com/actuator/health
# {"status":"UP"}
```

**Schemas were created.** Grab the external connection string from
*aegiszero-postgres → Connect*, then:

```bash
psql "<external connection string>" -c "\dn"
```

You should see `access`, `audit`, `auth`, `security`, `users` alongside
`public`. If they are missing, Flyway never ran — check the backend logs.

**End-to-end smoke test.** This is the real proof, because it crosses four
services and the event bus:

```bash
curl -X POST https://aegiszero-gateway.onrender.com/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","password":"CorrectHorse9!","firstName":"Ada","lastName":"Lovelace"}'
```

That single call should:

1. create a credential in `auth.credentials`,
2. publish `user.registered` to the Redis stream,
3. have `user-service` create a profile from it,
4. have `access-service` assign the default role from the same event,
5. have `notification-service` send a verification email.

Check the email arrived, then open the console at the frontend URL and log in.

To confirm events really are flowing through Redis rather than silently
dropping, connect to Redis (*aegiszero-redis → Connect*) and look at the stream:

```
XLEN user.registered
XINFO GROUPS user.registered
```

You should see a non-zero length and one consumer group per subscribing service
(`user-service`, `access-service`).

---

## Troubleshooting

**`database "auth_db" does not exist`** (or `user_db`, `access_db`, …)
The service is still using an old `DB_NAME`. Services read the real database
name off the instance, so this means either the Blueprint never re-synced, or
you are pointing at a Postgres instance created by an older `render.yaml`.
Check *service → Environment → `DB_NAME`*: it should be `aegiszero`, with
`DB_SCHEMA` set to that service's schema. If it says `auth_db`, delete the
Postgres instance and re-apply the Blueprint (Step 0).

**`BREVO_API_KEY is required when email.provider=brevo-api`**
Step 2. Set the variable and redeploy that service.

**`UnknownHostException: Failed to resolve 'aegiszero-x-service'` / `NXDOMAIN`,
every request through the gateway a fast `500`**
This is not a typo or a stale sync — no hostname fixes it. A free Render web
service cannot receive private-network traffic at all (Render's own docs:
*"Free web services can send private network requests, but they can't receive
them"*), so there is no address for any of the seven internal URLs in Step 2
to resolve to. The fix is the one in Step 2: point at each service's real
public `onrender.com` URL, not an internal name.

**`Port scan timeout reached, no open ports detected`**
A symptom, not a cause. The app crashed before binding its port — read the
exception above this line.

**Blueprint sync fails on `databaseName`**
That field is immutable after creation. Either delete the existing Postgres
instance, or set `databaseName` back to whatever the instance already has.
Nothing reads it — every service takes the name from the instance itself — so
either is safe.

**Browser console shows CORS errors**
`CORS_ALLOWED_ORIGINS` on the gateway does not match the frontend's real
origin. Step 4.

**`502 Bad Gateway` from the gateway**
A downstream service is asleep or still waking. Retry after 60 seconds; see
cold starts below.

**Verification emails never arrive**
The sender address in `MAIL_FROM` is not verified in Brevo. Check
`notification-service` logs for `Brevo API rejected email … HTTP 401` (bad API
key) or `HTTP 400` (unverified sender).

**Login hangs for a minute or more**
Normal on free tier when services are cold. See below.

---

## Free-tier limits worth knowing

- **Cold starts.** Every web service spins down after ~15 minutes idle and takes
  30–60s to wake. A login can chain gateway → auth → access → security, so the
  first request after a quiet period can take a couple of minutes. **Wake the
  demo a few minutes before showing it to anyone** — hitting the frontend and
  the gateway health endpoint is enough to start the chain.
- **Postgres expires.** The free Postgres plan is deleted roughly 30 days after
  creation unless you upgrade. Fine for a demo you are actively working on; do
  not leave it unattended for a month and expect it to still be there.
- **Redis is ~25MB.** Enough for sessions, MFA challenges and demo-level event
  traffic. Streams are capped with `XADD MAXLEN ~ 1000`
  (`aegiszero.events.redis.max-stream-length`) precisely so `audit.events`
  cannot fill it.
- **Memory is tight.** `JAVA_TOOL_OPTIONS` caps each JVM at a 300MB heap with
  SerialGC to fit a 512MB container. Under real concurrent load these will OOM.
  That is an accepted trade for a free portfolio deploy, not a production
  setting.

---

## Redeploying after a code change

The one non-obvious part of this layout. Application code lives in
**submodules**, and Render builds the root repo at whatever submodule commit is
pinned there. Pushing to a submodule alone changes nothing on Render.

```bash
# 1. commit and push inside the submodule
cd services
git add -A && git commit -m "fix: ..." && git push origin main

# 2. bump the pointer in the platform repo — this is the step people forget
cd ..
git add services
git commit -m "chore: bump services pointer"
git push origin main
```

Only that second push triggers a rebuild. Changes to `render.yaml`,
`docker-compose.yml`, `pom.xml` or the docs live in the root repo and take
effect on their own push.

To apply a `render.yaml` change: *Blueprints → your Blueprint → Sync*. Render
re-reads the file and updates the services; it will not touch immutable fields
on resources that already exist.
