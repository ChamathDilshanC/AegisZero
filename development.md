# AegisZero — Development Guide
## Zero-Trust Identity & Access Management Platform

This document provides the practical development roadmap for building the AegisZero platform from an empty repository to a portfolio-ready Spring Boot microservices application.

---

# 1. Development Goals

The first version should demonstrate:

- Enterprise-grade authentication
- JWT access and refresh tokens
- Role-Based Access Control (RBAC)
- Multi-Factor Authentication (MFA)
- Device recognition
- Session management
- Suspicious login detection
- Event-driven architecture with Kafka
- Audit logging
- API key management
- Security administration dashboard

Do not attempt to build every microservice on day one.

Build the system incrementally.

---

# 2. Recommended Development Order

```text
Phase 0  -> Project Setup
Phase 1  -> Authentication
Phase 2  -> User Management
Phase 3  -> Authorization / RBAC
Phase 4  -> Security Intelligence
Phase 5  -> Kafka Event Architecture
Phase 6  -> API Key Management
Phase 7  -> Frontend Security Console
Phase 8  -> Testing
Phase 9  -> Docker Deployment
Phase 10 -> Advanced Enterprise Features
```

---

# 3. Phase 0 — Project Setup

## 3.1 Create Repository

```text
aegiszero/
├── architecture.md
├── development.md
├── README.md
├── docker-compose.yml
├── .gitignore
├── .env.example
│
├── services/
├── frontend/
├── infrastructure/
└── shared/
```

## 3.2 Initial Services

Start with only:

```text
services/
├── api-gateway/
├── auth-service/
├── user-service/
├── access-service/
├── security-service/
├── audit-service/
└── notification-service/
```

## 3.3 Java Version

Recommended:

```text
Java 21 LTS
Spring Boot 3.x
Gradle or Maven
```

## 3.4 Common Spring Dependencies

Depending on the service:

```text
Spring Web
Spring Security
Spring Data JPA
Spring Validation
PostgreSQL Driver
Spring Boot Actuator
Lombok
Flyway
Spring for Apache Kafka
Spring Cloud Gateway
```

---

# 4. Phase 1 — Authentication Service

This is the first major service.

## Features

- User registration
- Login
- Logout
- Password hashing
- JWT access tokens
- Refresh tokens
- Refresh token rotation
- Email verification
- Password reset

## Package Structure

```text
auth-service/
└── src/main/java/com/aegiszero/auth/
    ├── AuthServiceApplication.java
    │
    ├── config/
    │   ├── SecurityConfig.java
    │   ├── JwtConfig.java
    │   └── ApplicationConfig.java
    │
    ├── controller/
    │   └── AuthController.java
    │
    ├── service/
    │   ├── AuthenticationService.java
    │   ├── RegistrationService.java
    │   ├── TokenService.java
    │   └── PasswordService.java
    │
    ├── repository/
    │   ├── CredentialRepository.java
    │   └── RefreshTokenRepository.java
    │
    ├── entity/
    │   ├── Credential.java
    │   └── RefreshToken.java
    │
    ├── dto/
    │   ├── LoginRequest.java
    │   ├── RegisterRequest.java
    │   ├── TokenResponse.java
    │   └── RefreshTokenRequest.java
    │
    ├── security/
    │   ├── JwtService.java
    │   └── PasswordEncoderConfig.java
    │
    ├── event/
    │   └── LoginEventPublisher.java
    │
    └── exception/
        ├── GlobalExceptionHandler.java
        └── InvalidCredentialsException.java
```

## Authentication API

```text
POST /api/auth/register
POST /api/auth/login
POST /api/auth/refresh
POST /api/auth/logout
POST /api/auth/forgot-password
POST /api/auth/reset-password
POST /api/auth/verify-email
```

## Login Implementation Flow

```text
LoginRequest
      │
      ▼
AuthController
      │
      ▼
AuthenticationService
      │
      ├── Find Credential
      │
      ├── Verify Password
      │
      ├── Check Account Status
      │
      ├── Publish Login Attempt
      │
      ├── Evaluate MFA Requirement
      │
      ├── Create Session
      │
      └── Generate Tokens
              │
              ▼
        TokenResponse
```

## Definition of Done

- [ ] Registration works
- [ ] Passwords are hashed
- [ ] Login works
- [ ] Invalid credentials are rejected
- [ ] Access token is generated
- [ ] Refresh token is generated
- [ ] Refresh token rotation works
- [ ] Logout revokes the session/token
- [ ] Unit tests exist

---

# 5. Phase 2 — User Service

Separate user profile data from authentication credentials.

## User Data

```text
id
email
first_name
last_name
avatar_url
status
created_at
updated_at
```

## APIs

```text
GET    /api/users/me
PUT    /api/users/me
GET    /api/users/{id}
PUT    /api/users/{id}
DELETE /api/users/{id}
```

## Definition of Done

- [ ] Profile creation
- [ ] Profile update
- [ ] Account status management
- [ ] Admin user listing
- [ ] Pagination
- [ ] Search

---

# 6. Phase 3 — Access Service

Implement authorization separately.

## Step 1: Create Permissions

```text
USER_READ
USER_CREATE
USER_UPDATE
USER_DELETE

ROLE_READ
ROLE_CREATE
ROLE_UPDATE
ROLE_DELETE

AUDIT_READ
AUDIT_EXPORT

API_KEY_CREATE
API_KEY_REVOKE
```

## Step 2: Create Roles

```text
SUPER_ADMIN
SECURITY_ADMIN
ADMIN
MANAGER
USER
READ_ONLY
```

## Step 3: Assign Permissions

```text
SUPER_ADMIN
    └── All permissions

SECURITY_ADMIN
    ├── AUDIT_READ
    ├── USER_READ
    ├── API_KEY_REVOKE
    └── SECURITY_MANAGE

USER
    └── PROFILE_READ
```

## APIs

```text
GET    /api/access/roles
POST   /api/access/roles
PUT    /api/access/roles/{id}
DELETE /api/access/roles/{id}

GET    /api/access/permissions
POST   /api/access/users/{userId}/roles
DELETE /api/access/users/{userId}/roles/{roleId}
```

## Definition of Done

- [ ] Roles CRUD
- [ ] Permissions CRUD
- [ ] Assign permissions to roles
- [ ] Assign roles to users
- [ ] Protect endpoints with permissions

---

# 7. Phase 4 — Security Service

Initially keep security features inside one service:

```text
security-service/
├── mfa/
├── devices/
├── sessions/
└── risk/
```

Later these can be extracted into independent microservices.

---

# 8. MFA Development

## Initial MFA Methods

Implement in this order:

```text
1. Email OTP
2. TOTP Authenticator
3. Recovery Codes
4. Passkeys/WebAuthn
```

## Email OTP Flow

```text
Login
  │
  ▼
Password Valid
  │
  ▼
MFA Required
  │
  ▼
Generate 6-digit OTP
  │
  ▼
Store hashed OTP + expiration
  │
  ▼
Send Email
  │
  ▼
POST /mfa/verify
  │
  ▼
Generate Session + Tokens
```

Recommended expiration:

```text
OTP TTL = 5 minutes
Maximum attempts = 5
```

---

# 9. Device Management Development

## Capture Device Metadata

From request headers/client data:

```text
User-Agent
Browser
Operating System
IP Address
Device ID/Fingerprint
```

## Device Logic

```text
Login
  │
  ▼
Calculate Device Identifier
  │
  ├── Existing Device -> Known Device
  │
  └── New Device
          │
          ▼
      Increase Risk Score
          │
          ▼
      Notify User
```

APIs:

```text
GET    /api/security/devices
DELETE /api/security/devices/{id}
POST   /api/security/devices/{id}/trust
POST   /api/security/devices/{id}/block
```

---

# 10. Session Management with Redis

## Redis Data Model

```text
session:{sessionId}

{
  userId,
  deviceId,
  createdAt,
  lastActivity,
  ipAddress
}
```

User session index:

```text
user:sessions:{userId}
```

## APIs

```text
GET    /api/security/sessions
DELETE /api/security/sessions/{id}
DELETE /api/security/sessions
```

The final endpoint logs the user out from all devices.

---

# 11. Suspicious Login Detection

Start with a rule-based engine.

## Risk Factors

```text
New Device              +25
New Country             +35
New IP Address          +15
Impossible Travel       +50
Failed Login Attempts   +25
Known Trusted Device    -20
Blocked IP              +100
```

## Example Java Model

```text
RiskScore = 0

if newDevice:
    RiskScore += 25

if newCountry:
    RiskScore += 35

if impossibleTravel:
    RiskScore += 50

if failedAttempts:
    RiskScore += 25
```

## Security Decisions

```text
0-30    -> ALLOW
31-60   -> REQUIRE_MFA
61-90   -> REQUIRE_ADDITIONAL_VERIFICATION
91+     -> BLOCK
```

## Development Tasks

- [ ] New device detection
- [ ] New IP detection
- [ ] Failed login tracking
- [ ] Risk scoring engine
- [ ] Security decision engine
- [ ] User alert generation

---

# 12. Phase 5 — Kafka Integration

Add Kafka only after the basic synchronous flow works.

## Event Flow

```text
Auth Service
     │
     ▼
LoginAttemptEvent
     │
     ▼
Kafka Topic
     │
 ┌───┼───────────────┐
 ▼   ▼               ▼
Risk Audit      Notification
```

## Event Classes

```text
LoginAttemptEvent
LoginSucceededEvent
LoginFailedEvent
PasswordChangedEvent
MfaEnabledEvent
DeviceRegisteredEvent
SessionRevokedEvent
ApiKeyCreatedEvent
```

## Recommended Kafka Topics

```text
auth.login.attempted
auth.login.succeeded
auth.login.failed

security.risk.calculated
security.alerts

audit.events
notification.events
```

## Important Rule

Use events for side effects and asynchronous processing.

Do not make the authentication process completely dependent on a slow Kafka consumer.

---

# 13. Audit Service Development

Every sensitive action should create an audit event.

## Audit Event Fields

```text
id
event_type
actor_id
target_id
ip_address
device_id
timestamp
correlation_id
metadata
```

## Example Events

```text
LOGIN_SUCCESS
LOGIN_FAILED
PASSWORD_CHANGED
MFA_ENABLED
MFA_DISABLED
ROLE_ASSIGNED
ROLE_REMOVED
API_KEY_CREATED
API_KEY_REVOKED
SESSION_REVOKED
DEVICE_BLOCKED
```

## Development Tasks

- [ ] Kafka audit consumer
- [ ] PostgreSQL audit storage
- [ ] Search API
- [ ] Date filtering
- [ ] Event type filtering
- [ ] User filtering
- [ ] Export functionality

---

# 14. API Key Management

## API Key Format

Example:

```text
az_live_************************
```

Never store the complete raw key.

## Creation Flow

```text
Generate random secret
       │
       ▼
Show raw key once
       │
       ▼
Hash secret
       │
       ▼
Store prefix + hash
```

Database fields:

```text
id
name
key_prefix
key_hash
owner_id
expires_at
revoked_at
last_used_at
created_at
```

Scopes:

```text
users.read
users.write
audit.read
sessions.manage
```

---

# 15. Notification Service

Initial delivery channels:

```text
Email
```

Future:

```text
Push Notifications
SMS
Slack/Webhooks
```

Notifications:

```text
New device login
Suspicious login blocked
Password changed
MFA enabled/disabled
API key created
API key revoked
```

---

# 16. API Gateway Development

Responsibilities:

```text
Routing
JWT validation
Rate limiting
Request logging
Correlation IDs
CORS
```

Suggested route structure:

```text
/api/auth/**       -> auth-service
/api/users/**      -> user-service
/api/access/**     -> access-service
/api/security/**   -> security-service
/api/audit/**      -> audit-service
```

Add rate limiting to:

```text
/api/auth/login
/api/auth/register
/api/auth/forgot-password
/api/mfa/**
```

---

# 17. Frontend Development

Recommended:

```text
Next.js
TypeScript
Tailwind CSS
TanStack Query
```

## Pages

```text
/
├── login
├── register
├── forgot-password
├── mfa-challenge
│
└── dashboard
    ├── overview
    ├── users
    ├── roles
    ├── permissions
    ├── devices
    ├── sessions
    ├── security-events
    ├── audit-logs
    └── api-keys
```

## Dashboard Widgets

```text
Total Users
Active Sessions
Failed Logins
High Risk Events
MFA Enabled Users
Active API Keys
```

---

# 18. Testing Strategy

## Unit Tests

Use:

```text
JUnit 5
Mockito
```

Test:

```text
Password verification
JWT generation
Risk scoring
Permission evaluation
OTP validation
API key validation
```

## Integration Tests

Use:

```text
Testcontainers
PostgreSQL
Redis
Kafka
```

## Security Tests

Test:

- Unauthorized requests
- Expired JWT
- Invalid JWT signature
- Refresh token reuse
- Brute-force login attempts
- Missing permissions
- MFA bypass attempts
- Revoked API keys

---

# 19. Docker Development

Start all infrastructure using Docker Compose.

```text
docker compose up -d postgres redis kafka
```

Then run services locally during development.

Later:

```text
docker compose up --build
```

Recommended infrastructure:

```text
PostgreSQL
Redis
Kafka
Kafka UI
Prometheus
Grafana
```

---

# 20. Database Migration Strategy

Use Flyway.

Example:

```text
src/main/resources/db/migration/

V1__create_credentials.sql
V2__create_refresh_tokens.sql
V3__add_account_status.sql
V4__add_password_reset_tokens.sql
```

Never manually modify production schemas without migrations.

---

# 21. Configuration Strategy

Do not commit secrets.

```text
application.yml
application-local.yml
application-dev.yml
application-prod.yml
```

Example environment variables:

```text
DB_URL
DB_USERNAME
DB_PASSWORD

JWT_PRIVATE_KEY
JWT_PUBLIC_KEY

REDIS_HOST
KAFKA_BOOTSTRAP_SERVERS

EMAIL_USERNAME
EMAIL_PASSWORD
```

For local development, use environment variables or a secure secrets mechanism.

---

# 22. Suggested Weekly Development Roadmap

## Week 1

```text
Repository setup
Docker infrastructure
PostgreSQL
Redis
API Gateway
Auth service skeleton
```

## Week 2

```text
Registration
Login
Password hashing
JWT
Refresh tokens
```

## Week 3

```text
User service
Profile management
Account status
Admin user APIs
```

## Week 4

```text
Roles
Permissions
RBAC
Endpoint protection
```

## Week 5

```text
MFA
Email OTP
TOTP
Recovery codes
```

## Week 6

```text
Device tracking
Session management
Redis session storage
```

## Week 7

```text
Kafka
Login events
Risk engine
Suspicious login detection
```

## Week 8

```text
Audit service
Notification service
Security alerts
```

## Week 9

```text
API key management
Scopes
Revocation
Usage tracking
```

## Week 10

```text
Next.js dashboard
Security analytics
Users
Devices
Sessions
Audit logs
```

## Week 11

```text
Testing
Testcontainers
Security testing
Performance testing
```

## Week 12

```text
Docker deployment
CI/CD
Monitoring
Portfolio documentation
Demo video
```

---

# 23. Recommended Git Branch Strategy

```text
main
develop
feature/auth-login
feature/jwt
feature/refresh-token
feature/rbac
feature/mfa
feature/devices
feature/sessions
feature/risk-engine
feature/kafka-events
feature/audit
feature/api-keys
```

Merge workflow:

```text
feature branch
      │
      ▼
Pull Request
      │
      ▼
develop
      │
      ▼
Release
      │
      ▼
main
```

---

# 24. CI/CD Pipeline

Recommended pipeline:

```text
Push
 │
 ▼
Run Tests
 │
 ▼
Static Analysis
 │
 ▼
Build Application
 │
 ▼
Build Docker Image
 │
 ▼
Dependency Security Scan
 │
 ▼
Push Image Registry
 │
 ▼
Deploy
```

GitHub Actions jobs:

```text
test
build
docker
security-scan
deploy
```

---

# 25. Definition of Portfolio-Ready

The project is portfolio-ready when it demonstrates:

- [ ] Microservices architecture
- [ ] API Gateway
- [ ] JWT authentication
- [ ] Refresh token rotation
- [ ] RBAC authorization
- [ ] MFA
- [ ] Device intelligence
- [ ] Session management
- [ ] Redis integration
- [ ] Kafka events
- [ ] Risk scoring
- [ ] Audit logging
- [ ] API key management
- [ ] Admin dashboard
- [ ] Docker Compose
- [ ] Automated tests
- [ ] CI/CD pipeline
- [ ] Architecture documentation

---

# 26. Final Development Priority

Build in this exact priority:

```text
1. Auth Service
2. User Service
3. Access Service
4. API Gateway
5. Security Service
6. Audit Service
7. Kafka
8. Notification Service
9. API Key Service
10. Frontend
11. Monitoring
12. Deployment
```

The most important rule is:

> Build a complete, working small version first. Split and scale the architecture only after the core flows are stable.

---

# Final MVP Target

A user should be able to:

```text
Register
   ↓
Verify Email
   ↓
Login
   ↓
Risk Evaluation
   ↓
MFA Challenge if required
   ↓
Receive JWT + Refresh Token
   ↓
Access authorized APIs
   ↓
View active devices and sessions
   ↓
Revoke a suspicious session
   ↓
Generate an audit trail
```

At this point, AegisZero becomes a strong, realistic, enterprise-style Java Spring Boot portfolio project.
