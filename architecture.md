# Zero-Trust Identity & Access Management Platform
## Complete Spring Boot Microservices Architecture

## 1. Project Overview

A Zero-Trust Identity and Access Management (IAM) platform that provides centralized authentication, authorization, multi-factor authentication, device/session control, API key management, suspicious-login detection, audit logging, and security analytics for multiple client applications.

### Core Zero-Trust Principle

> Never trust implicitly. Continuously verify identity, device, session, permissions, and risk before granting access.

The platform can serve multiple applications:

```text
Web Application ─────┐
Mobile Application ──┤
Admin Portal ────────┼──> Zero-Trust IAM Platform
Third-Party Services ┤
Internal APIs ───────┘
```

---

# 2. High-Level Architecture

```text
                                  ┌─────────────────────┐
                                  │     Next.js UI      │
                                  │ Admin / User Portal │
                                  └──────────┬──────────┘
                                             │ HTTPS
                                             ▼
                                  ┌─────────────────────┐
                                  │     API Gateway     │
                                  │ Spring Cloud Gateway│
                                  └──────────┬──────────┘
                                             │
              ┌──────────────────────────────┼──────────────────────────────┐
              ▼                              ▼                              ▼
     ┌─────────────────┐            ┌─────────────────┐            ┌─────────────────┐
     │  Auth Service   │            │  User Service   │            │ Access Service  │
     │ Login / Tokens  │            │ Profiles        │            │ RBAC / Policies │
     └────────┬────────┘            └────────┬────────┘            └────────┬────────┘
              │                              │                              │
              ├──────────────┐               │               ┌──────────────┤
              ▼              ▼               ▼               ▼              ▼
     ┌────────────────┐ ┌───────────────┐ ┌───────────────┐ ┌────────────┐ ┌─────────────┐
     │ MFA Service    │ │ Device Service│ │Session Service│ │ API Key    │ │ Audit       │
     │ OTP / TOTP     │ │ Trusted Devices│ │ Redis Sessions│ │ Service    │ │ Service     │
     └────────────────┘ └───────────────┘ └───────────────┘ └────────────┘ └──────┬──────┘
                                                                                    │
                                                                                    ▼
                                                                         ┌─────────────────┐
                                                                         │ PostgreSQL      │
                                                                         │ Audit Database  │
                                                                         └─────────────────┘

                         ┌───────────────────────────────────────────────────────────┐
                         │                        KAFKA                              │
                         │ login-events | security-events | audit-events | alerts   │
                         └────────────────────────────┬──────────────────────────────┘
                                                      │
                                 ┌────────────────────┼────────────────────┐
                                 ▼                    ▼                    ▼
                        ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
                        │ Risk Service    │  │ Notification    │  │ Analytics       │
                        │ Threat Scoring  │  │ Email / Alerts  │  │ Security Stats  │
                        └─────────────────┘  └─────────────────┘  └─────────────────┘
```

---

# 3. Repository Structure

Recommended monorepo structure:

```text
zero-trust-iam/
│
├── architecture.md
├── README.md
├── docker-compose.yml
├── .env.example
│
├── infrastructure/
│   ├── postgres/
│   ├── kafka/
│   ├── redis/
│   ├── nginx/
│   └── monitoring/
│       ├── prometheus/
│       └── grafana/
│
├── services/
│   ├── api-gateway/
│   ├── auth-service/
│   ├── user-service/
│   ├── access-service/
│   ├── mfa-service/
│   ├── device-service/
│   ├── session-service/
│   ├── api-key-service/
│   ├── audit-service/
│   ├── risk-service/
│   ├── notification-service/
│   └── analytics-service/
│
├── frontend/
│   └── security-console/
│
└── shared/
    ├── common-events/
    ├── common-messaging/
    ├── common-security/
    └── common-exceptions/
```

For the first MVP, start with fewer services and split later:

```text
api-gateway
auth-service
user-service
access-service
security-service
audit-service
notification-service
```

---

# 4. Microservice Responsibilities

## 4.1 API Gateway

**Technology:** Spring Cloud Gateway

Responsibilities:

- Single entry point
- Route requests to services
- Rate limiting
- Request correlation IDs
- JWT validation
- IP filtering
- CORS
- API versioning

Example routes:

```text
/api/auth/**        -> auth-service
/api/users/**       -> user-service
/api/access/**      -> access-service
/api/security/**    -> security-service
/api/audit/**       -> audit-service
```

---

## 4.2 Auth Service

Responsible for:

- Registration
- Login
- Logout
- Password verification
- Password reset
- Email verification
- JWT access token generation
- Refresh token rotation
- OAuth2/OIDC integration

### Package Structure

```text
auth-service/
└── src/main/java/com/zerotrust/auth/
    ├── config/
    ├── controller/
    ├── service/
    ├── repository/
    ├── entity/
    ├── dto/
    ├── security/
    ├── event/
    └── exception/
```

Main APIs:

```text
POST /auth/register
POST /auth/login
POST /auth/refresh
POST /auth/logout
POST /auth/forgot-password
POST /auth/reset-password
POST /auth/verify-email
```

Login flow:

```text
Client
  │
  ▼
POST /auth/login
  │
  ▼
Validate email/password
  │
  ├── Invalid ──> LOGIN_FAILED event
  │
  ▼
Create LOGIN_ATTEMPT event
  │
  ▼
Risk evaluation
  │
  ├── High risk ──> MFA / BLOCK
  │
  ▼
Generate JWT
  │
  ▼
Create session
  │
  ▼
LOGIN_SUCCESS event
```

---

## 4.3 User Service

Responsible for:

- User profile
- Account status
- User preferences
- Account lifecycle
- Tenant/organization membership

Main entities:

```text
User
Organization
UserOrganization
```

---

## 4.4 Access Service

Responsible for authorization.

Implements:

- RBAC
- Permission management
- Optional ABAC/policy rules

Entity model:

```text
User
  │
  └── UserRole
         │
         ▼
        Role
         │
         └── RolePermission
                 │
                 ▼
             Permission
```

Example permissions:

```text
USER_READ
USER_CREATE
USER_UPDATE
USER_DELETE

ROLE_READ
ROLE_ASSIGN

AUDIT_READ
AUDIT_EXPORT

API_KEY_CREATE
API_KEY_REVOKE
```

APIs:

```text
GET  /access/roles
POST /access/roles
PUT  /access/roles/{id}
POST /access/users/{userId}/roles
POST /access/check
```

---

## 4.5 MFA Service

Supports:

- TOTP authenticator applications
- Email OTP
- Backup recovery codes
- Future: WebAuthn / Passkeys

Flow:

```text
Password Login
      │
      ▼
MFA Required?
   │       │
  No      Yes
   │       │
   ▼       ▼
Token   MFA Challenge
            │
            ▼
        Verify OTP
            │
      ┌─────┴─────┐
      ▼           ▼
   Invalid      Valid
      │           │
   Reject        Token
```

---

## 4.6 Device Service

Tracks:

- Browser/device fingerprint
- Device name
- Operating system
- Browser
- Last IP
- Last known location
- Trusted status
- Blocked status

Example table:

```text
devices
- id
- user_id
- fingerprint
- device_name
- browser
- operating_system
- trusted
- blocked
- last_ip
- last_seen_at
- created_at
```

---

## 4.7 Session Service

Use Redis for fast session operations.

Responsibilities:

- Active sessions
- Refresh-token/session association
- Session revocation
- Concurrent session limits
- Logout from all devices

Redis key examples:

```text
session:{sessionId}
user:sessions:{userId}
token:blacklist:{tokenId}
```

APIs:

```text
GET    /sessions
DELETE /sessions/{id}
DELETE /sessions/all
```

---

## 4.8 API Key Service

Provides machine-to-machine authentication.

Features:

- Create API keys
- Hash keys before storage
- Scope permissions
- Expiration
- Rotation
- Revocation
- Last-used tracking

Never store raw API keys.

Example:

```text
Raw key shown once:
zt_live_xxxxxxxxxxxxxxxxx

Database:
key_prefix = zt_live_ab12
key_hash   = bcrypt/argon2 hash
```

---

## 4.9 Audit Service

Consumes events from Kafka and stores immutable security history.

Audit event example:

```json
{
  "eventId": "uuid",
  "eventType": "PASSWORD_CHANGED",
  "actorId": "user-123",
  "targetId": "user-123",
  "ipAddress": "x.x.x.x",
  "timestamp": "2026-08-23T10:00:00Z",
  "metadata": {}
}
```

Important events:

```text
LOGIN_SUCCESS
LOGIN_FAILED
MFA_ENABLED
MFA_FAILED
PASSWORD_CHANGED
ROLE_CHANGED
API_KEY_CREATED
API_KEY_REVOKED
SESSION_TERMINATED
DEVICE_BLOCKED
```

---

## 4.10 Risk Service

Calculates suspicious-login risk.

### Initial Rule-Based Score

```text
New device                 +25
New country                +35
Impossible travel          +50
Multiple failed logins     +25
Blocked IP                 +80
Known trusted device       -20
```

Decision:

```text
0 - 30     LOW       -> Allow
31 - 60    MEDIUM    -> Require MFA
61 - 90    HIGH      -> Extra verification
91+        CRITICAL  -> Block + alert
```

Later, replace or supplement rules with anomaly detection.

---

## 4.11 Notification Service

Kafka consumer for:

- Security alerts
- Login notifications
- Password reset emails
- MFA OTP emails
- New device alerts

---

## 4.12 Analytics Service

Generates:

- Failed login trends
- Active sessions
- High-risk events
- Most targeted accounts
- Geographic activity
- API key usage

---

# 5. Kafka Event Architecture

Recommended topics:

```text
auth.login.attempted
auth.login.succeeded
auth.login.failed

security.risk.calculated
security.mfa.required
security.alert.triggered

user.password.changed
user.role.changed

device.registered
device.blocked

session.created
session.revoked

audit.events
notification.events
```

Event flow:

```text
Auth Service
    │
    ▼
auth.login.attempted
    │
    ├──────────────► Risk Service
    │                     │
    │                     ▼
    │              security.risk.calculated
    │                     │
    │          ┌──────────┼──────────┐
    │          ▼          ▼          ▼
    │        MFA       Audit     Notification
```

---

# 6. Database Architecture

Prefer database-per-service.

```text
PostgreSQL Server
│
├── auth_db
├── user_db
├── access_db
├── device_db
├── api_key_db
├── audit_db
└── analytics_db
```

Do not directly join tables across microservice databases.

Services communicate through:

- REST/gRPC for synchronous communication
- Kafka for asynchronous events

---

# 7. Core PostgreSQL Tables

## auth_db

```text
credentials
refresh_tokens
password_reset_tokens
email_verification_tokens
oauth_accounts
```

## user_db

```text
users
organizations
user_organizations
```

## access_db

```text
roles
permissions
role_permissions
user_roles
```

## security_db

```text
mfa_methods
recovery_codes
devices
sessions
blocked_ips
risk_events
```

## audit_db

```text
audit_logs
security_events
```

## api_key_db

```text
api_keys
api_key_scopes
api_key_usage
```

---

# 8. Authentication Token Design

Use short-lived access tokens and rotating refresh tokens.

```text
Access Token:
TTL = 5 to 15 minutes

Refresh Token:
TTL = 7 to 30 days
Rotated on use
Stored securely
```

JWT claims example:

```json
{
  "sub": "user-uuid",
  "sid": "session-uuid",
  "roles": ["ADMIN"],
  "permissions": ["USER_READ", "AUDIT_READ"],
  "iss": "zero-trust-iam",
  "aud": "client-application",
  "exp": 1234567890
}
```

For production, consider asymmetric signing:

```text
Private Key -> Auth Service signs JWT
Public Key  -> Gateway/Resource Services verify JWT
```

---

# 9. Security Dashboard Architecture

Frontend modules:

```text
Dashboard
├── Overview
├── Security Events
├── Active Sessions
├── Devices
├── Users
├── Roles & Permissions
├── API Keys
├── Audit Logs
├── Risk Alerts
└── Organization Settings
```

Dashboard widgets:

```text
Total Users
Active Sessions
Failed Logins Today
High Risk Attempts
MFA Adoption Rate
Active API Keys
Security Alerts
```

---

# 10. Recommended Tech Stack

## Backend

```text
Java 21+
Spring Boot 3.x
Spring Security
Spring Cloud Gateway
Spring Data JPA
Spring Validation
Spring Kafka
Spring Boot Actuator
```

## Security

```text
OAuth2
OpenID Connect
JWT
TOTP
Argon2 or BCrypt
WebAuthn (Phase 2)
```

## Infrastructure

```text
PostgreSQL
Redis
Apache Kafka
Docker
Kubernetes (optional advanced deployment)
```

## Frontend

```text
Next.js
TypeScript
Tailwind CSS
shadcn/ui or custom design system
TanStack Query
```

## Observability

```text
Prometheus
Grafana
OpenTelemetry
Jaeger
ELK/OpenSearch
```

---

# 11. Docker Development Architecture

```text
docker-compose.yml
│
├── postgres
├── redis
├── kafka
├── kafka-ui
├── api-gateway
├── auth-service
├── user-service
├── access-service
├── security-service
├── audit-service
├── notification-service
└── frontend
```

Local request path:

```text
Browser
   │
   ▼
localhost:3000
   │
   ▼
API Gateway :8080
   │
   ├── Auth Service :8081
   ├── User Service :8082
   ├── Access Service :8083
   ├── Security Service :8084
   ├── Audit Service :8085
   └── Notification Service :8086
```

---

# 12. Recommended Development Phases

## Phase 1 — Strong Authentication MVP

Build:

- User registration
- Login
- JWT
- Refresh tokens
- Password hashing
- Logout
- Email verification
- Basic audit logging

Services:

```text
api-gateway
auth-service
user-service
audit-service
```

## Phase 2 — Authorization

Build:

- Roles
- Permissions
- RBAC
- Permission checks
- Admin user management

Add:

```text
access-service
```

## Phase 3 — Zero-Trust Security

Build:

- MFA
- Device tracking
- Session management
- Trusted devices
- New-device detection

## Phase 4 — Event-Driven Security

Add Kafka.

Build:

- Login events
- Risk scoring
- Security alerts
- Notification pipeline
- Audit event consumers

## Phase 5 — Advanced Enterprise Features

Build:

- API key management
- OAuth2/OIDC provider support
- Multi-tenancy
- WebAuthn/passkeys
- Policy engine
- Advanced analytics

---

# 13. MVP Service Structure Recommendation

Do not start with 12 microservices immediately.

Start with:

```text
zero-trust-iam/
├── api-gateway/
├── auth-service/
├── user-service/
├── access-service/
├── security-service/
├── audit-service/
├── notification-service/
├── frontend/
└── infrastructure/
```

Then split `security-service` into:

```text
mfa-service
device-service
session-service
risk-service
api-key-service
```

when the application grows.

---

# 14. Production Security Checklist

- [ ] Passwords hashed with Argon2id or BCrypt
- [ ] No raw passwords in logs
- [ ] No raw API keys stored
- [ ] Short-lived access tokens
- [ ] Refresh token rotation
- [ ] Refresh token reuse detection
- [ ] HTTPS everywhere
- [ ] Rate limiting
- [ ] Account lockout / progressive delays
- [ ] MFA for sensitive operations
- [ ] Audit logging
- [ ] Secrets outside source control
- [ ] Database encryption/backups
- [ ] Security headers
- [ ] Input validation
- [ ] Dependency vulnerability scanning
- [ ] Centralized monitoring and alerting

---

# 15. Final Architecture Recommendation

For a portfolio-quality but realistically buildable version:

```text
                    Next.js Security Console
                              │
                              ▼
                     Spring Cloud Gateway
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
     Auth Service        User Service       Access Service
          │                   │                   │
          └───────────────────┼───────────────────┘
                              ▼
                      Security Service
                 MFA / Devices / Sessions / Risk
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
                  Redis               PostgreSQL
                              │
                              ▼
                             Kafka
                 ┌────────────┼────────────┐
                 ▼            ▼            ▼
             Audit       Notification   Analytics
```

## Portfolio Project Title

**AegisZero — Zero-Trust Identity & Access Management Platform**

Suggested one-line description:

> An enterprise-grade Zero-Trust IAM platform built with Spring Boot microservices, providing adaptive authentication, MFA, device and session intelligence, granular authorization, API security, event-driven threat detection, and immutable audit logging.
