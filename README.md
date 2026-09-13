<div align="center">

# Airymax Docker Deployment

> Official containerized deployment for the Airymax AI Agent Runtime Platform —
> multi-stage, security-hardened OCI images plus Docker Compose orchestration
> for development, staging and production.

**Language:** English | [简体中文](README_zh.md)

Powered by OpenAirymax

[![License](https://img.shields.io/badge/license-AGPL--3.0+Apache--2.0-4a90d9)](LICENSE)
[![Branch](https://img.shields.io/badge/branch-main-6f42c1)](https://atomgit.com/openairymax/docker)

[![Docker](https://img.shields.io/badge/Docker-24.0+-2496ED?logo=docker&logoColor=white)](https://www.docker.com)
[![Compose](https://img.shields.io/badge/Docker%20Compose-2.20+-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![Ubuntu](https://img.shields.io/badge/base%20image-ubuntu%2024.04-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com)

</div>

---

## Overview

The **Docker module** is the official containerized deployment layer for the
Airymax platform. It packages the AgentRT runtime, daemon services, gateway,
OpenLab and the desktop web frontend into reproducible OCI images, and provides
three Docker Compose manifests (development / staging / production). The
staging and production stacks add PostgreSQL, Redis and a Prometheus + Grafana
observability stack; an Alertmanager routing template is provided under
`monitoring/` for optional deployments. This is one of the three leaf
repositories under the [`products/`](https://atomgit.com/openairymax/products)
management repo, alongside `desktop` (personal client) and `memoryrovol`
(commercial memory provider).

The module ships **four multi-stage Dockerfiles** — `Dockerfile.kernel`,
`Dockerfile.daemon`, `Dockerfile.openlab` and `Dockerfile.desktop` — each
producing one or more named build targets (builder / runtime / gateway / debug
/ production / development). The development manifest assembles a complete
runtime topology: a microkernel container, thirteen daemon containers managed
by `supervisord` (`a2a_d`, `agent_d`, `channel_d`, `cupolas_d`, `hook_d`,
`llm_d`, `market_d`, `mem_d`, `monit_d`, `notify_d`, `sched_d`, `think_d`,
`tool_d`) and a three-protocol (HTTP / WebSocket / stdio) gateway. The staging
and production manifests extend this with PostgreSQL for relational storage,
Redis for cache, sessions and rate limiting, Prometheus + Grafana for
monitoring, plus the OpenLab and desktop web frontends.

The production manifest implements a CIS Docker Benchmark-aligned security
baseline across all services: `no-new-privileges:true`, `read_only`
filesystems, `cap_drop: ALL`, a seccomp syscall whitelist
(`config/seccomp-profile.json`) on the kernel container, non-root runtime
users (`agentrt`, UID/GID 1000, for kernel and daemons; `openlab` for
OpenLab), structured JSON log rotation, and `HEALTHCHECK` probes in every
first-party image. Linting and scanning policy files (`.hadolint.yaml`,
`.trivy.yml`) are included for integration with external image scanners. The
module targets DevOps engineers, SREs and enterprise operators who need to
run and observe Airymax in production.

## Directory Structure

```
docker/
├── Dockerfile.kernel          # Kernel image (ubuntu:24.04; builder/runtime/debug)
├── Dockerfile.daemon          # Daemon / Gateway image (ubuntu:24.04, supervisord)
├── Dockerfile.openlab         # OpenLab image (python:3.12-slim; backend-builder/
│                              #   production/development)
├── Dockerfile.desktop         # Desktop web image (node:20-slim builder +
│                              #   nginx:1.27-alpine runtime)
│
├── docker-compose.yml         # Development stack (kernel + 13 daemons + gateway)
├── docker-compose.staging.yml # Staging stack (full topology, monitoring enabled)
├── docker-compose.prod.yml    # Production stack (security-hardened)
│
├── .env.example               # Dev env template
├── .env.staging.example       # Staging env template
├── .env.production.example    # Production env template
│
├── config/                    # Runtime configuration (baked into images)
│   ├── gateway.yaml           #   Gateway: bind 0.0.0.0:18789, HTTP/WS/stdio, CORS
│   ├── seccomp-profile.json   #   seccomp syscall whitelist (kernel container)
│   ├── supervisor/
│   │   └── supervisord.conf   #   supervisord main configuration
│   ├── nginx/                 #   Reverse proxy & static site configs
│   │   ├── openlab.conf  desktop.conf  agentrt-proxy.conf
│   └── logging/
│       └── fluent-bit.conf    #   Optional Fluent Bit log shipping template
│
├── monitoring/                # Observability configuration
│   ├── prometheus.yml         #   Scrape config (kernel / gateway / prometheus)
│   ├── alertmanager.yml       #   Alertmanager routing template (webhook + SMTP)
│   ├── rules/                 #   Alert rules (kernel.yml, agentrt_alerts.yml)
│   └── grafana/               #   Provisioned datasources + dashboards
│
├── scripts/                   # Operations tooling
│   ├── quick-start.sh         #   Interactive launcher (dev/staging/prod/stop/clean)
│   ├── install.sh             #   One-shot installer
│   ├── healthcheck.sh         #   Multi-service health probe (text/JSON)
│   ├── backup.sh              #   Backup / restore / verify / list / clean
│   ├── generate-secrets.sh    #   Random secret generator (writes secrets/*.txt)
│   ├── harden.sh              #   OS & service hardening appliance
│   ├── openlab-entrypoint.sh  #   OpenLab container entrypoint
│   └── verify-build.sh        #   Post-build verification
│
├── secrets/                   # Generated secret files (gitignored) + guide
├── tests/                     # Integration test suite (tests/integration/)
├── .github/                   # CI workflows (license & manifest validation)
├── .trivy.yml                 # Trivy scan policy (external scanner integration)
├── .hadolint.yaml             # Dockerfile linter config
├── .dockerignore
│
├── DEPLOYMENT.md              # Step-by-step deployment walkthrough
├── CHANGELOG.md               # Release history
├── release.json               # Release metadata
├── LICENSE                    # AGPL-3.0 + Apache-2.0 dual text
├── NOTICE                     # Copyright & third-party notice
├── README.md                  # This file
└── README_zh.md               # 简体中文版
```

## Features / Components

### Images & Build Targets

Images follow the naming scheme
`${DOCKER_REGISTRY:-spharx}/agentrt-<component>:${AGENTRT_VERSION:-0.1.1}`;
both the registry and the version tag are configurable via environment.

| Image | Dockerfile | Targets | Container ports | Purpose |
|-------|-----------|---------|-----------------|---------|
| `agentrt-kernel` | `Dockerfile.kernel` | `builder`, `runtime`, `debug` | `18080/tcp` (IPC API) · `9090/tcp` (metrics) | Microkernel core — IPC, memory, task, time |
| `agentrt-<name>_d` / `agentrt-gateway` | `Dockerfile.daemon` | `builder`, `runtime`, `gateway`, `debug` | `8080/tcp` · `8081/tcp` (EXPOSE) | The thirteen supervisor-managed daemons; the `gateway` target serves the three-protocol gateway (HTTP / WebSocket / stdio, see `config/gateway.yaml`) |
| `agentrt-openlab` | `Dockerfile.openlab` | `backend-builder`, `production`, `development` | `8000/tcp` (API) · `443/tcp` (web, production) · `5173/tcp` (dev server, development) | OpenLab interactive platform — Python backend + Nginx static |
| `agentrt-desktop` | `Dockerfile.desktop` | `builder`, `production` | `80/tcp` | Static web build of the desktop client served by Nginx |

> Note: the daemon image `EXPOSE`s 8080/8081 for the supervisor-managed daemon
> processes; the gateway container's listen ports are set by its configuration
> (18789 API + 18790 admin in staging/production) and mapped to the host via
> `GATEWAY_PORT` / `GATEWAY_ADMIN_PORT`.

### Compose-orchestrated Services

`docker-compose.yml` (dev) launches the kernel plus thirteen daemon containers
and the gateway — 15 services in total:

| Service | Role |
|---------|------|
| `kernel` | Microkernel IPC core, the single authority for every daemon |
| `a2a_d` | A2A agent communication daemon |
| `agent_d` | Agent lifecycle daemon |
| `channel_d` | Channel service daemon |
| `cupolas_d` | Security dome daemon (permissions / sanitization / audit) |
| `hook_d` | Hook registration and trigger daemon |
| `llm_d` | LLM service daemon |
| `market_d` | Tool marketplace daemon |
| `mem_d` | Memory storage daemon |
| `monit_d` | Monitoring & observability daemon |
| `notify_d` | Notification push daemon |
| `sched_d` | Task scheduling daemon |
| `think_d` | Dual-thinking daemon |
| `tool_d` | Tool execution daemon |
| `gateway` | HTTP/WS/stdio gateway fronting the kernel (target: `gateway`) |

The staging and production manifests add `postgres`, `redis`, `prometheus`,
`grafana`, `desktop`, and `openlab` (enabled via the `openlab` Compose
profile).

### Port Plan

Host-side exposure is controlled by environment variables, so the same
manifests adapt to dev and hardened deployments:

| Container port | Service | Host publishing | Use |
|----------------|---------|-----------------|-----|
| 18789 | Gateway API (HTTP + WebSocket) | `${GATEWAY_PORT}` — dev fallback `8080`, staging/prod fallback `18789`; `.env.example` pins `18789` | Unified external API entry |
| 18790 | Gateway Admin API | `${GATEWAY_ADMIN_PORT:-18790}` (staging/prod) | Management API (restrict source IPs) |
| 8080 / 8081 | Daemon processes (supervisord) | Not published | Internal daemon HTTP/status |
| 18080 | Kernel IPC API | `${KERNEL_IPC_PORT:-18080}` in dev only — not published in staging/prod | Syscall API (gateway-facing) |
| 9090 | Kernel metrics | Not published; scraped in-network | Prometheus `/metrics` |
| 8000 | OpenLab API | `${OPENLAB_API_PORT:-8000}` | OpenLab backend |
| 443 / 5173 | OpenLab web (production / development) | `${OPENLAB_WEB_PORT:-443}` | OpenLab frontend |
| 80 | Desktop web (Nginx) | `${DESKTOP_PORT:-8080}` (prod) | Desktop client static site |
| 5432 | PostgreSQL | Not published | Relational store |
| 6379 | Redis | Not published | Cache, sessions, rate limiting |
| 9090 | Prometheus | `127.0.0.1:${PROMETHEUS_PORT:-9091}` (prod) | Monitoring UI / API, loopback only |
| 3000 | Grafana | `${GRAFANA_PORT:-3000}` (prod) | Dashboards |

### Tech Stack

| Layer | Technology |
|-------|-----------|
| Base images | `ubuntu:24.04` (kernel/daemon), `python:3.12-slim` (openlab), `node:20-slim` (desktop builder), `nginx:1.27-alpine` (desktop runtime) |
| Build toolchain | GCC 12, CMake 3.28 + Ninja 1.11 (pinned in `Dockerfile.kernel`), Python 3.12 venv, `npm ci` |
| Process supervisor | `supervisord` for daemon/gateway containers |
| Orchestration | Docker Compose v2 (dev / staging / prod) |
| Data stores | `postgres:16-alpine`, `redis:7.2-alpine` |
| Observability | `prom/prometheus:v2.50.0`, `grafana/grafana:10.3.0`; Alertmanager routing template in `monitoring/` |
| Logging | `json-file` driver with size/count rotation (`LOG_MAX_SIZE` / `LOG_MAX_FILE`) |
| Security | seccomp (kernel), `cap_drop: ALL`, read-only FS, `no-new-privileges`, non-root runtime users |
| CI | License check + Dockerfile/Compose manifest validation (`.github/workflows/`) |

### Security Baseline

The production manifest applies the following controls to **all** services
(`kernel`, `gateway`, `postgres`, `redis`, `openlab`, `prometheus`, `grafana`,
`desktop`):

| Control | Implementation |
|---------|----------------|
| Trusted base images | Official `ubuntu:24.04`, `python:3.12-slim`, `node:20-slim`, `nginx:1.27-alpine` |
| HEALTHCHECK | All four first-party images define health probes |
| Non-root runtime | Kernel and daemons run as `agentrt` (UID/GID 1000, no login shell); OpenLab runs as `openlab` |
| seccomp | `config/seccomp-profile.json` syscall whitelist on the kernel container |
| Read-only filesystem | `read_only: true` on every production service |
| Capability drop | `cap_drop: ALL`; a minimal `cap_add` only where a service requires it |
| No new privileges | `no-new-privileges:true` on every production service |
| Log driver | `json-file` with `max-size` / `max-file` rotation per service |

Secrets are never hardcoded: each stack loads its configuration from an env
file (`--env-file`). `scripts/generate-secrets.sh` writes strong random
secrets as `600`-permission files under `secrets/` (gitignored), ready to be
referenced from `.env.production`; `secrets/` also documents an optional
Docker Secrets workflow for Swarm deployments — see
[`secrets/README.md`](secrets/README.md).

## Upstream Dependencies

```
   ┌────────────────────────────────────────┐
   │  AgentRT source tree (workspace root)  │
   │  kernel · daemons · gateway · openlab  │
   └───────────────────┬────────────────────┘
                       │ COPY sources at build time
                       ▼
   ┌────────────────────────────────────────┐
   │        products/docker (images)        │
   │  kernel · daemon · openlab · desktop   │
   └───────────────────┬────────────────────┘
                       │ docker compose up
                       ▼
   ┌────────────────────────────────────────┐
   │        Operators / Enterprise          │
   │     (Dev, Staging, Production)         │
   └────────────────────────────────────────┘
```

- **AgentRT runtime source tree** — kernel + daemons + gateway + OpenLab
  sources, `COPY`-ed into each builder stage at image build time. All three
  manifests set the build context to the workspace root (`context: ../..`),
  so the four Dockerfiles read the runtime sources directly.
- **Runtime configuration** — `config/` (gateway.yaml, supervisord.conf,
  nginx, Fluent Bit) is copied into the runtime stages and baked into the
  images.
- **`products/desktop` source** — consumed by `Dockerfile.desktop` to build
  the web frontend image (pure Vite build served by Nginx; no Tauri native
  shell).
- **Third-party OCI images** — `ubuntu:24.04`, `python:3.12-slim`,
  `node:20-slim`, `nginx:1.27-alpine`, `postgres:16-alpine`,
  `redis:7.2-alpine`, `prom/prometheus:v2.50.0`, `grafana/grafana:10.3.0`.
  These retain their upstream licenses.

## Downstream Consumers

- **Operators / enterprise deployments** — run the produced images in dev,
  staging and production via the three Compose manifests. The kernel is a
  stateful core and ships with `KERNEL_REPLICAS=1`; scale stateless components
  via Compose as needed.
- **`products/desktop` users** — can point the desktop client at the gateway
  published by a locally launched stack (host port controlled by
  `GATEWAY_PORT`).
- **`products/` management repo** — pins this repository as a git submodule
  for coordinated releases. Releases are tagged per `release.json` and
  `CHANGELOG.md`.
- **Optional: `products/memoryrovol`** — the commercial memory provider can
  be linked into the AgentRT runtime at build time by configuring the runtime
  with `-DAIRY_WITH_MEMORYROVOL=ON` and `AIRY_MEMORY_BACKEND=memoryrovol`
  before containerization, unlocking the commercial memory features under the
  SPHARX commercial EULA.

## Build / Installation

### Prerequisites

| Component | Minimum | Recommended (Prod) |
|-----------|---------|--------------------|
| OS | Ubuntu 20.04+ / CentOS 8+ | Ubuntu 22.04 LTS (hardened) |
| CPU | 4 cores | 16+ cores |
| Memory | 8 GB | 32+ GB |
| Disk | 50 GB SSD | 500+ GB SSD |
| Docker Engine | 20.10.0 | 24.0.0 |
| Docker Compose | 2.0.0 (V2 plugin) | 2.20.0 |
| Utilities | `git`, `curl`, `jq`, `openssl` | same |

```bash
# Ubuntu install example
sudo apt-get update && sudo apt-get install -y \
    docker.io docker-compose-v2 git curl jq openssl

# Allow the current user to run Docker without sudo
sudo usermod -aG docker "$USER" && newgrp docker
```

### Quick start (development)

```bash
# 1. Clone
git clone https://atomgit.com/openairymax/docker.git
cd docker

# 2. Configure environment
cp .env.example .env

# 3. Launch the dev stack (kernel + 13 daemons + gateway)
docker compose -f docker-compose.yml --env-file .env up -d

# 4. Verify health
./scripts/healthcheck.sh
# Expected: Overall Status: HEALTHY
```

With the shipped `.env.example`, the gateway API is published at
`localhost:18789` (`GATEWAY_PORT`) and the kernel IPC API at `localhost:18080`
(`KERNEL_IPC_PORT`).

Alternative launcher:

```bash
./scripts/quick-start.sh dev   # Interactive launcher (env check + menu)
```

### Staging deployment

`docker-compose.staging.yml` mirrors the production topology with isolated
data volumes and monitoring enabled by default. It is intended for
pre-release validation, soak tests and regression tests.

```bash
cp .env.staging.example .env.staging
# Edit .env.staging — fill in strong secrets
docker compose -f docker-compose.staging.yml --env-file .env.staging up -d
./scripts/healthcheck.sh --json
```

### Production deployment

```bash
# 1. Create the production env file
cp .env.production.example .env.production
chmod 600 .env.production

# 2. Generate strong random secrets — writes 600-permission files under
#    secrets/ (postgres_password.txt, redis_password.txt, jwt_secret.txt,
#    grafana_password.txt, plus optional LLM API key files). Copy the values
#    into .env.production.
./scripts/generate-secrets.sh

# 3. Launch the hardened production stack
docker compose -f docker-compose.prod.yml \
    --env-file .env.production up -d

# 4. Verify
./scripts/healthcheck.sh --json

# 5. (Optional) Create the first backup
./scripts/backup.sh backup --env prod
```

### Verification

```bash
# Gateway health (host port = ${GATEWAY_PORT}; 18789 with the shipped templates)
curl -fsS http://localhost:18789/api/v1/health

# Kernel IPC (dev only — not published in staging/production)
curl -fsS http://localhost:18080/api/v1/health

# Database
docker compose -f docker-compose.prod.yml exec postgres pg_isready -U agentrt

# Redis
docker compose -f docker-compose.prod.yml exec redis \
    sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli ping'
```

### Common operations

```bash
docker compose -f docker-compose.yml ps                # List services
docker compose logs -f gateway kernel                  # Follow logs
docker compose exec kernel bash                        # Shell into a container
docker stats --no-stream                               # Resource snapshot
./scripts/healthcheck.sh --json --service gateway      # Probe a single service
./scripts/backup.sh list                               # List backups
./scripts/backup.sh restore <file>.tar.gz --env prod   # Disaster recovery
./scripts/harden.sh verify                             # Audit hardening status
./scripts/harden.sh all                                # Apply full hardening baseline
./scripts/quick-start.sh stop                          # Stop a running stack
```

See [`DEPLOYMENT.md`](DEPLOYMENT.md) for the full deployment walkthrough
(reverse proxy, TLS, backup scheduling, performance tuning).

### Branch Strategy

- Active development branch: **`main`**
- The `products/` management repo tracks this repository via git submodule
  pointers.
- Releases are tagged per `release.json` and `CHANGELOG.md`.

## License

This repository is dual-licensed:

- **GNU Affero General Public License v3.0 or later** (AGPL-3.0-or-later)
- **Apache License, Version 2.0**

You may choose either license at your option. The full text of both licenses
is included in the [`LICENSE`](LICENSE) file. The SPDX expression is:

```
AGPL-3.0-or-later OR Apache-2.0
```

See [`NOTICE`](NOTICE) for copyright, trademark and third-party component
notices. The bundled third-party images (PostgreSQL, Redis, Prometheus,
Grafana, Nginx, Ubuntu, Python, Node) retain their upstream licenses. The
optional `memoryrovol` memory provider is distributed separately under the
SPHARX commercial EULA and is not covered by this repository's licenses.

```
Repository:  https://atomgit.com/openairymax/docker.git
Branch:      main
SPDX:        AGPL-3.0-or-later OR Apache-2.0
```

Copyright (c) 2025-2026 SPHARX Ltd. All Rights Reserved.
