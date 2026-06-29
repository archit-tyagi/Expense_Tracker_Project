# 💸 ExpenseTracker

> ExpenseTracker reads the transaction messages your bank already sends you, understands them with AI, and turns them into a clean, searchable record of where your money goes.

Every card swipe, UPI payment, or bank transfer fires off an SMS or alert like *“INR 450 debited from A/C XX1234 at STARBUCKS on 25-Jun”*. Instead of letting those pile up unread, ExpenseTracker ingests them, uses a Large Language Model to pull out the **amount, merchant, currency, and date**, and files each one away automatically — so your spending is tracked without you lifting a finger. Then just ask for this month’s expenses, filter by any date range, or see exactly where your money went, all through a secure API.

Under the hood it’s a polyglot (Java + Python) microservices system: secured at the edge by an API gateway, wired together over an event-streaming backbone, and packaged to spin up with a single command.

**📖 Live API Docs:** _<!-- TODO: add GitHub Pages URL -->_

---

## 📑 Table of Contents

- [Why this project](#-why-this-project)
- [Key Features](#-key-features)
- [Architecture](#-architecture)
- [Services](#-services)
- [How It Works](#-how-it-works)
- [Tech Stack](#-tech-stack)
- [API Documentation](#-api-documentation)
- [Getting Started](#-getting-started)
- [Repositories & Docker Images](#-repositories--docker-images)
- [Project Structure](#-project-structure)

---

## 🎯 Why this project

ExpenseTracker demonstrates how a modern backend system is designed and operated end-to-end:

- **Independent microservices** that can be built, deployed, and scaled separately.
- **Security at the edge** — every request is authenticated by an API gateway before it ever reaches a service.
- **Event-driven communication** — services collaborate through a message stream instead of brittle direct calls.
- **AI in the pipeline** — natural-language input is converted into structured data by a Large Language Model.
- **Containerised everything** — the whole platform spins up with a single `docker compose` command.

This repository (`ExpenseTracker/`) is the **orchestration / infrastructure layer**: it contains the Docker Compose files, the API gateway configuration, the database bootstrap, and the API documentation site. Each application service lives in **its own repository** and ships as **its own Docker image** (links in the [Repositories & Docker Images](#-repositories--docker-images) section).

---

## ✨ Key Features

- 🔐 **Centralised JWT authentication** enforced at the gateway — services never see an unauthenticated request.
- 🤖 **AI-powered expense capture** — bank transaction messages are parsed into structured expenses (amount, merchant, currency, date) by an LLM.
- 📨 **Event-driven architecture** — services communicate asynchronously over Apache Kafka.
- 🧩 **Polyglot microservices** — Java/Spring Boot for transactional services, Python for the AI service.
- 🗄️ **Database-per-service** — each service owns its own schema for true decoupling.
- 📚 **Unified, single-origin API documentation** via Swagger UI behind the gateway.
- 🐳 **One-command local startup** with Docker Compose.

---

## 🏗 Architecture

ExpenseTracker follows the **API Gateway + Microservices** pattern. Clients only ever talk to **Kong** (the gateway); Kong authenticates the request, then forwards it to the right service.

```
                                   ┌──────────────────────────────────────────────┐
                                   │                  CLIENT                       │
                                   │        (web / mobile / curl / Swagger UI)     │
                                   └───────────────────────┬──────────────────────┘
                                                           │  HTTPS + Bearer (JWT)
                                                           ▼
                            ┌───────────────────────────────────────────────────────┐
                            │              KONG API GATEWAY  (:8000)                 │
                            │  • single entry point                                  │
                            │  • custom-auth plugin → validates token, injects       │
                            │    X-User-Id header, refreshes expired tokens          │
                            └───┬───────────────┬───────────────┬───────────────┬────┘
                                │               │               │               │
                  validate token│               │               │               │
                                ▼               ▼               ▼               ▼
                       ┌────────────┐   ┌────────────┐   ┌────────────┐   ┌──────────────┐
                       │   auth     │   │   user     │   │  expense   │   │   message    │
                       │  service   │   │  service   │   │  service   │   │   service    │
                       │  (:9090)   │   │  (:9091)   │   │  (:9094)   │   │   (:8010)    │
                       │  Java      │   │  Java      │   │  Java      │   │  Python+LLM  │
                       └─────┬──────┘   └─────┬──────┘   └─────┬──────┘   └──────┬───────┘
                             │                │                │                 │
                             │                │                │   expense_Event │ publish
                             │                │                │◀────────────────┘
                             ▼                ▼                ▼        (Apache Kafka topic)
                       ┌──────────────────────────────────────────────────────┐
                       │                       MySQL                            │
                       │   authServiceDB   userServiceDB   expenseServiceDB     │
                       └──────────────────────────────────────────────────────┘
```

**In simple terms:**
1. A client logs in and receives a **JWT** (a signed access token).
2. Every subsequent request goes to the gateway with that token attached.
3. The gateway’s **custom auth plugin** checks the token with the auth service. If valid, it tags the request with the user’s ID (`X-User-Id`) and passes it on; if not, it’s rejected at the door.
4. Downstream services trust that injected header — they never have to handle tokens themselves.
5. The **message service** uses AI to turn messages into expenses and announces them on a **Kafka** event stream; the **expense service** listens and records them.

---

## 🧩 Services

| Service | What it does | Stack | Port | Data store |
|---------|--------------|-------|------|------------|
| **auth-service** | User registration, login/logout, JWT issuance & validation (the gateway calls `/auth/v1/ping` to verify tokens) | Java · Spring Boot · Spring Security | `9090` | MySQL `authServiceDB` |
| **user-service** | Create / read / update the user’s profile | Java · Spring Boot · Spring Data JPA | `9091` | MySQL `userServiceDB` |
| **expense-service** | Add, update, fetch, list & date-range-filter expenses; consumes AI-generated expense events | Java · Spring Boot · JPA · Kafka | `9094` | MySQL `expenseServiceDB` |
| **message-service** | Parses free-text messages into structured expenses using an **LLM**, then publishes an expense event | Python · OpenAI API · Kafka | `8010` | _stateless_ |

> 🔗 Repository and Docker image links for each service are in [Repositories & Docker Images](#-repositories--docker-images).

---

## ⚙️ How It Works

### 1) Authentication flow

```
signup ─▶ login ─▶ receive JWT ─▶ call API via gateway ─▶ gateway validates ─▶ service responds
```

1. **Sign up** — `POST /auth/v1/signup` creates an account (public endpoint).
2. **Log in** — `POST /auth/v1/login` returns an **access token** and **refresh token**.
3. **Call any protected API** through Kong (`http://localhost:8000/...`) with header `Authorization: Bearer <token>`.
4. Kong’s `custom-auth` plugin calls `auth-service /auth/v1/ping` to validate the token and resolve the user id.
5. On success, Kong injects an **`X-User-Id`** header and forwards the request; on failure it returns `401`.
6. If the access token had expired, the auth service mints a fresh one and the gateway returns it to the client in the `Authorization` response header — seamless token refresh.

### 2) AI-powered expense ingestion

```
bank transaction message ─▶ message-service (LLM parse) ─▶ Kafka "expense_Event" ─▶ expense-service ─▶ MySQL
```

1. A bank transaction message is sent to `POST /message/v1/process` (e.g. *“INR 450 debited from A/C XX1234 at STARBUCKS on 25-Jun”*).
2. **message-service** calls the **LLM** to extract a structured expense (amount, merchant, currency, timestamp).
3. It **publishes** an event to the Kafka topic **`expense_Event`**.
4. **expense-service** consumes the event and **persists** the expense to its database.
5. The user can now retrieve it via `GET /expense/v1/getAllExpenses` or filter by date range via `GET /expense/v1/filterExpenses`.

---

## 🛠 Tech Stack

| Category | Technologies |
|----------|--------------|
| **Backend services** | Java, Spring Boot, Spring Security, Spring Data JPA, Spring Kafka |
| **AI service** | Python, OpenAI API (LLM-based message parsing) |
| **API Gateway** | Kong (declarative/DB-less config) + custom Lua authentication plugin |
| **Messaging / Eventing** | Apache Kafka (KRaft mode — no ZooKeeper) |
| **Database** | MySQL (database-per-service) |
| **API Documentation** | OpenAPI 3 / Swagger UI (springdoc) |
| **DevOps / Runtime** | Docker, Docker Compose |

---

## 📚 API Documentation

All four services publish OpenAPI specs, surfaced through a **single, unified Swagger UI**.

- **Live (when the stack is running):** open **`http://localhost:8000/swagger-ui/`** — served through the gateway so there are no cross-origin issues. Use the dropdown to switch between Auth, User, Expense, and Message services.
- **Hosted docs:** _<!-- TODO: add hosted docs URL (e.g. GitHub Pages) -->_

**Endpoint cheat-sheet** (all paths are relative to the gateway, `http://localhost:8000`):

| Service | Endpoint | Description |
|---------|----------|-------------|
| Auth | `POST /auth/v1/signup` | Register a new user (public) |
| Auth | `POST /auth/v1/login` | Log in, returns access + refresh tokens (public) |
| Auth | `POST /auth/v1/logout` | Revoke the refresh token |
| User | `GET /user/v1/getUser` | Get the current user’s profile |
| User | `PUT /user/v1/updateUser` | Create / replace the profile (full update) |
| User | `PATCH /user/v1/patchUser` | Update only the supplied profile fields |
| Expense | `POST /expense/v1/addExpense` | Add an expense |
| Expense | `GET /expense/v1/getAllExpenses` | List all expenses |
| Expense | `GET /expense/v1/getExpense?expenseId=` | Get a single expense |
| Expense | `GET /expense/v1/filterExpenses?from=&to=` | Filter by date-time range |
| Expense | `PUT /expense/v1/updateExpense` | Replace an existing expense (full update) |
| Expense | `PATCH /expense/v1/patchExpense?expenseId=` | Update only the supplied expense fields |
| Expense | `DELETE /expense/v1/deleteExpense?expenseId=` | Delete an expense |
| Message | `POST /message/v1/process` | Parse a bank transaction message into an expense |

---

## 🚀 Getting Started

### Prerequisites

- [Docker](https://www.docker.com/) & Docker Compose
- The four service images available locally or pullable (see [Repositories & Docker Images](#-repositories--docker-images))

### 1. Pull the service images

```bash
docker pull archittyagi221/auth-service:latest
docker pull archittyagi221/message-service:latest
docker pull archittyagi221/expense-service:latest
docker pull archittyagi221/user-service:latest
docker pull archittyagi221/kong:latest
```

### 2. Launch the whole platform

```bash
docker compose -f expenseTracker-compose.yml up
```

This starts Kafka, MySQL, the four services, Kong, and Swagger UI, with health checks and the correct start-up ordering already wired in.

### 3. Smoke-test through the gateway

```bash
# Register
curl -X POST http://localhost:8000/auth/v1/signup \
  -H "Content-Type: application/json" \
  -d '{"username":"jane","password":"secret","email":"jane@example.com"}'

# Log in (grab the token from the Authorization response header)
curl -i -X POST http://localhost:8000/auth/v1/login \
  -H "Content-Type: application/json" \
  -d '{"username":"jane","password":"secret"}'

# Capture an expense from natural language
curl -X POST http://localhost:8000/message/v1/process \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"message":"Spent 450 at Starbucks today"}'

# Read it back
curl http://localhost:8000/expense/v1/getAllExpenses \
  -H "Authorization: Bearer <token>"
```

> 💡 Browse the interactive docs at `http://localhost:8000/swagger-ui/` once the stack is healthy.

---

## 🔗 Repositories & Docker Images

> Fill in the links below — each application service is maintained in its own repository and published as its own image.

| Service             | Source Repository | Docker Image |
|---------------------|-------------------|--------------|
| **auth-service**    | _<!-- TODO: add GitHub repo URL -->_ | _<!-- TODO: add Docker image URL -->_ |
| **user-service**    | _<!-- TODO: add GitHub repo URL -->_ | _<!-- TODO: add Docker image URL -->_ |
| **expense-service** | _<!-- TODO: add GitHub repo URL -->_ | _<!-- TODO: add Docker image URL -->_ |
| **message-service** | _<!-- TODO: add GitHub repo URL -->_ | _<!-- TODO: add Docker image URL -->_ |
| **kong**            | _<!-- TODO: add GitHub repo URL -->_ | _<!-- TODO: add Docker image URL -->_ |
---

## 📂 Project Structure

```
ExpenseTracker/                     # Orchestration / infrastructure repo (this repo)
├── expenseTracker-compose.yml      # Full-stack Docker Compose (all services + infra)
├── kong/                           # API gateway
│   ├── config/kong.yml             #   Declarative routes & services
│   ├── custom-plugins/custom-auth/ #   Custom Lua auth plugin (token validation + X-User-Id)
│   └── kong-compose.yml
├── kafka/
│   └── kafka-compose.yml           # Apache Kafka (KRaft mode)
├── mysql/
│   ├── init.sql                    # Creates per-service databases
│   └── mysql-compose.yml
└── docs/                           # API documentation site (Swagger UI + OpenAPI specs)
    ├── index.html
    ├── swagger/                    #   Swagger UI assets
    └── openapi/                    #   auth / user / expense / message OpenAPI specs
```

---