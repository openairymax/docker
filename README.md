<div align="center">

# Airymax Docker Deployment

> Official containerized deployment for the Airymax AI Agent Runtime Platform —
> multi-stage, security-hardened OCI images plus Docker Compose orchestration
> for development, staging and production.

**Language:** English | [简体中文](README_zh.md)

Powered by OpenAirymax

[![Version](https://img.shields.io/badge/version-0.1.1-5a6b7e)](https://atomgit.com/openairymax/docker/releases)
[![License](https://img.shields.io/badge/license-AGPL--3.0+Apache--2.0-4a90d9)](LICENSE)
[![Branch](https://img.shields.io/badge/branch-feature%2Fofficial--hubs--01-6f42c1)](https://atomgit.com/openairymax/docker)

[![Docker](https://img.shields.io/badge/Docker-24.0+-2496ED?logo=docker&logoColor=white)](https://www.docker.com)
[![Compose](https://img.shields.io/badge/Docker%20Compose-2.20+-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![Ubuntu](https://img.shields.io/badge/base%20image-ubuntu%2024.04-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com)

</div>

---

## Overview

The **Docker module** is the official containerized deployment layer for the
Airymax platform. It packages the AgentRT runtime, daemon services, gateway,
OpenLab and the desktop web frontend into reproducible OCI images, and provides
three Docker Compose manifests (development / staging / production) that wire
them together with PostgreSQL, Redis and a full Prometheus + Grafana +
AlertManager observability stack. It is one of the three leaf repositories
under the [`products/`](https://atomgit.com/openairymax/products) management
repo, alongside `desktop` (personal client) and `memoryrovol` (commercial
memory provider).

The module ships **four multi-stage Dockerfiles** — `Dockerfile.kernel`,
`Dockerfile.daemon`, `Dockerfile.openlab` and `Dockerfile.desktop` — each
producing one or more named build targets (builder / runtime / gateway / debug
/ production / development). The Compose manifests assemble these images into a
complete runtime topology: a microkernel container fronts six
supervisor-managed daemons (`market_d`, `monit_d`, `notify_d`, `observe_d`,
`sched_d`, `tool_d`) and a three-protocol (HTTP / WebSocket / stdio) gateway,
backed by PostgreSQL for relational storage and Redis for IPC cache,
sessions and rate limiting.

The deployment implements a CIS Docker Benchmark 1.5+ aligned security baseline
across all production services: non-root `agentrt:1000` user, `read_only`
filesystems, `config/seccomp-profile.json` syscall whitelist, `cap_drop: ALL`,
`no-new-privileges: true`, structured JSON log rotation, layered HEALTHCHECK
probes on every service, and `${VAR:?error}` enforcement so the stack fails
fast on any missing secret. Trivy scans run on every CI build. The module
targets DevOps engineers, SREs and enterprise operators who need to run, scale
and observe Airymax in production.

## Directory Structure

```
docker/
├── Dockerfile.kernel          # Kernel image (ubuntu:24.04 multi-stage)
├── Dockerfile.daemon          # Daemon / Gateway image (supervisord-managed)
├── Dockerfile.openlab         # OpenLab image (python:3.12-slim + nginx)
├── Dockerfile.desktop         # Desktop web image (node:20 + nginx:1.27)
│
├── docker-compose.yml         # Development stack
├── docker-compose.staging.yml # Staging stack (1:1 mirror of production)
├── docker-compose.prod.yml    # Production stack (security-hardened)
│
├── .env.example                       # Dev env template
├── .env.staging.example               # Staging env template
├── .env.production.example            # Production env template (with secret gen)
│
├── config/                            # Runtime configuration
│   ├── gateway.yaml                   #   Gateway: protocols, rate limit, JWT, upstream
│   ├── seccomp-profile.json           #   seccomp syscall whitelist (CIS 5.7)
│   ├── supervisor/                    #   supervisord main + per-daemon conf.d/
│   ├── nginx/                         #   Reverse proxy + desktop/openlab static conf
│   │   ├── openlab.conf  desktop.conf  agentrt-proxy.conf
│   └── logging/                       #   Fluent Bit log aggregation templates
│       └── fluent-bit.conf
│
├── monitoring/                        # Observability stack
│   ├── prometheus.yml                 #   Scrape config (kernel/gateway/postgres/redis)
│   ├── alertmanager.yml               #   Alert routing (PagerDuty/Slack/Email)
│   ├── rules/                         #   Alert rule files
│   │   ├── kernel.yml  agentrt_alerts.yml
│   └── grafana/                       #   Provisioned datasources + dashboards
│
├── scripts/                           # Operations tooling
│   ├── quick-start.sh                 #   Interactive launcher (env check + menu)
│   ├── install.sh                     #   One-shot installer
│   ├── healthcheck.sh                 #   Multi-layer health probe (text/JSON)
│   ├── backup.sh                      #   Backup / restore / verify / list (GPG + SHA256)
│   ├── generate-secrets.sh            #   Strong random secret generator
│   ├── harden.sh                      #   Security hardening appliance
│   ├── openlab-entrypoint.sh          #   OpenLab container entrypoint
│   └── verify-build.sh                #   Post-build verification
│
├── secrets/                           # Docker Secrets templates & guide
├── tests/integration/                 # Integration test suite (test_services.py)
├── .github/                           # CI workflows (build → scan → test → publish)
├── .trivy.yml                         # Trivy vulnerability scan policy
├── .hadolint.yaml                     # Dockerfile linter config
├── .dockerignore
│
├── DEPLOYMENT.md                      # Step-by-step deployment walkthrough
├── CHANGELOG.md                       # Release history
├── release.json                       # Release metadata
├── LICENSE                            # AGPL-3.0 + Apache-2.0 dual text
├── NOTICE                             # Copyright & third-party notice
├── README.md                          # This file
└── README_zh.md                       # 简体中文版
```

## Features / Components

### Images & Build Targets

| Image | Dockerfile | Targets | Ports | Purpose |
|-------|-----------|---------|-------|---------|
| `spharx/agentrt-kernel` | `Dockerfile.kernel` | `builder`, `runtime`, `debug` | `18080/tcp` (IPC API) · `9090/tcp` (metrics) | Microkernel core — IPC, memory, task, time |
| `spharx/agentrt-daemon` / `agentrt-gateway` | `Dockerfile.daemon` | `builder`, `runtime`, `gateway`, `debug` | `18789/tcp` (API) · `18790/tcp` (admin) | Supervisor-managed daemons and three-protocol gateway (HTTP / WebSocket / stdio) |
| `spharx/agentrt-openlab` | `Dockerfile.openlab` | `backend-builder`, `production`, `development` | `8000/tcp` (API) · `80/tcp` / `443/tcp` (web) · `5173/tcp` (dev) | OpenLab interactive platform — Python backend + Nginx static |
| `spharx/agentrt-desktop` | `Dockerfile.desktop` | `builder`, `production` | `80/tcp` | Static web build of the desktop client served by Nginx |

### Compose-orchestrated Daemon Services

`docker-compose.yml` (dev) launches the kernel plus six supervisor-managed
daemons and the gateway:

| Service | Role |
|---------|------|
| `kernel` | Microkernel IPC core, the only upstream for every daemon |
| `market_d` | Market scheduling daemon |
| `monit_d` | Monitoring daemon |
| `notify_d` | Notification daemon |
| `observe_d` | Observation daemon |
| `sched_d` | Scheduling daemon |
| `tool_d` | Tool dispatch daemon |
| `gateway` | HTTP/WS/stdio gateway fronting the kernel (target: `gateway`) |

### Port Plan

| Port | Service | Exposure | Use |
|------|---------|----------|-----|
| **18789** | Gateway API | Public | Unified external API entry |
| **18790** | Gateway Admin | Restricted | Management API (IP-restricted) |
| 18080 | Kernel IPC | Internal | Syscall API (gateway only) |
| 9090 | Kernel Metrics | Internal | Prometheus `/metrics` |
| 5432 | PostgreSQL | Internal | Relational store (HeapStore slow tier) |
| 6379 | Redis | Internal | IPC cache, sessions, rate limiting |
| 9091 | Prometheus | Restricted | Monitoring UI (VPN-only in prod) |
| 3000 | Grafana | Restricted | Dashboards (VPN-only in prod) |

### Tech Stack

| Layer | Technology |
|-------|-----------|
| Base images | `ubuntu:24.04` (kernel/daemon), `python:3.12-slim` (openlab), `node:20-slim` (desktop builder), `nginx:1.27-alpine` (static servers) |
| Build toolchain | GCC 12, CMake 3.22 + Ninja, Python 3.12 venv, npm ci |
| Process supervisor | `supervisord` for daemon/gateway containers |
| Orchestration | Docker Compose v2 (dev / staging / prod) |
| Data stores | PostgreSQL 15-alpine, Redis 7-alpine |
| Observability | Prometheus v2.45, Grafana 10.2, AlertManager |
| Logging | JSON-file driver with rotation + optional Fluent Bit sidecar |
| Security | seccomp, cap_drop ALL, read-only FS, non-root `agentrt:1000` |
| CI/CD | GitHub Actions (Buildx multi-arch + Trivy scan + SARIF) |

### Security Baseline (CIS Docker Benchmark 1.5+)

| CIS | Control | Implementation |
|-----|---------|----------------|
| 4.1 | Trusted base images | Official `ubuntu:24.04`, `python:3.12-slim`, `nginx:1.27-alpine` |
| 4.6 | HEALTHCHECK | Every service has a layered health probe |
| 5.4 | Rootless containers | `USER agentrt:1000` (UID/GID 1000, shell `/sbin/nologin`) |
| 5.7 | seccomp | `config/seccomp-profile.json` whitelist |
| 5.9 | Read-only filesystem | `read_only: true` on production services |
| 5.10 | Drop suid/sgid | `cap_drop: ALL` |
| 5.11 | No new privileges | `no-new-privileges:true` |
| 5.26 | Capability whitelist | `cap_add: NET_BIND_SERVICE` only |
| 5.29 | Log driver config | `json-file` with `max-size` + `max-file` rotation |

Secrets are never hardcoded: production manifests use `${VAR:?error}` to fail
fast on missing values, and `secrets/` documents a Docker Secrets workflow.
Trivy scans run in CI on every build.

## Upstream Dependencies

```
   ┌─────────────────────────────────┐
   │  AgentRT runtime (sdk/agentrt)  │
   │  ecosystem/manager configs      │
   └────────────────┬────────────────┘
                    │ COPY sources at build time
                    ▼
   ┌─────────────────────────────────┐
   │     products/docker (images)    │
   │   Dockerfile.kernel             │
   │   Dockerfile.daemon             │
   │   Dockerfile.openlab            │
   │   Dockerfile.desktop            │
   └────────────────┬────────────────┘
                    │ docker compose up
                    ▼
   ┌─────────────────────────────────┐
   │  Operators / Enterprise         │
   │  (Dev, Staging, Production)     │
   └─────────────────────────────────┘
```

- **`AgentRT/` runtime source tree** — kernel + daemons + gateway + OpenLab
  sources, `COPY`-ed into each builder stage at image build time. The build
  context is the umbrella root (`context: ..`), so all four Dockerfiles read
  the runtime sources directly.
- **`ecosystem/manager/` configuration defaults** — consumed via `config/`
  (gateway.yaml, supervisor conf.d, nginx, Fluent Bit) and baked into the
  runtime images.
- **`products/desktop` source** — consumed by `Dockerfile.desktop` to build
  the web frontend image (pure Vite build, no Tauri native shell). The build
  copies `Desktop/` and runs `npm ci && npm run build`.
- **Third-party OCI images** — `ubuntu:24.04`, `python:3.12-slim`,
  `node:20-slim`, `nginx:1.27-alpine`, `postgres:15-alpine`,
  `redis:7-alpine`, `prom/prometheus`, `grafana/grafana`,
  `prom/alertmanager`. These retain their upstream licenses.

## Downstream Consumers

- **Operators / enterprise deployments** — run the produced images in dev,
  staging and production via the three Compose manifests. Stack scaling is
  supported (e.g. `docker compose up --scale kernel=3`).
- **`products/desktop` end users** — may run the desktop client alongside a
  locally launched `docker compose` stack as their gateway backend
  (default `localhost:18789`).
- **Airymax Hub umbrella** — pins this leaf repo as a git submodule on the
  `feature/official-hubs-01` branch for coordinated releases. Releases are
  tagged from the release branch (see `release.json` and `CHANGELOG.md`).
- **Optional: `products/memoryrovol`** — the commercial memory provider can be
  linked into the AgentRT runtime at build time via
  `-DAGENTRT_WITH_MEMORYROVOL=ON` before the runtime is containerized by this
  module, unlocking L3/L4 memory capabilities under a commercial EULA.

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
| Utilities | `git`, `curl`, `jq`, `openssl`, `make` | same |

```bash
# Ubuntu install example
sudo apt-get update && sudo apt-get install -y \
    docker.io docker-compose-v2 git curl jq openssl make

# Allow the current user to run Docker without sudo
sudo usermod -aG docker "$USER" && newgrp docker
```

### Quick start (development)

```bash
# 1. Clone (leaf repos live on the feature/official-hubs-01 branch)
git clone -b feature/official-hubs-01 git@atomgit.com:openairymax/docker.git
cd docker

# 2. Configure environment (defaults target localhost:18789)
cp .env.example .env

# 3. Launch the dev stack (kernel + 6 daemons + gateway)
docker compose -f docker-compose.yml --env-file .env up -d

# 4. Verify health
./scripts/healthcheck.sh
# Expected: Overall Status: HEALTHY
```

Alternative launchers:

```bash
./scripts/quick-start.sh dev   # Interactive launcher
make dev                       # Makefile shortcut
make dev-full                  # Same, but also starts the monitoring profile
```

### Staging deployment

`docker-compose.staging.yml` is a 1:1 replica of the production stack with
isolated data volumes and the monitoring profile enabled by default. It is
intended for pre-release validation, soak tests and regression tests.

```bash
cp .env.staging.example .env.staging
# Edit .env.staging — fill in strong secrets
docker compose -f docker-compose.staging.yml --env-file .env.staging up -d
./scripts/healthcheck.sh --env staging --json
```

### Production deployment

```bash
# 1. Create the production env file (mandatory secrets are enforced via ${VAR:?})
cp .env.production.example .env.production
chmod 600 .env.production

# 2. Generate strong random secrets
./scripts/generate-secrets.sh            # Writes POSTGRES_PASSWORD, REDIS_PASSWORD,
                                          # GATEWAY_JWT_SECRET, OPENLAB_SECRET_KEY, ...

# 3. Launch the hardened production stack
docker compose -f docker-compose.prod.yml \
    --env-file .env.production up -d

# 4. Verify
./scripts/healthcheck.sh --env prod --json

# 5. (Optional) Create the first backup
./scripts/backup.sh backup --env prod
```

### Verification

```bash
# Gateway health
curl -fsS http://localhost:18789/api/v1/health

# Kernel IPC (dev only — internal in prod)
curl -fsS http://localhost:18080/api/v1/health

# Database
docker compose exec postgres pg_isready -U agentrt

# Redis
docker compose exec redis sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli ping'
```

### Common operations

```bash
docker compose -f docker-compose.yml ps                 # List services
docker compose logs -f gateway kernel                    # Follow logs
docker compose exec kernel bash                          # Shell into a container
docker compose -f docker-compose.prod.yml up -d --scale kernel=3   # Scale kernel
docker stats --no-stream                                 # Resource snapshot
./scripts/backup.sh list                                 # List backups
./scripts/backup.sh restore <file>.tar.gz --env prod     # Disaster recovery
./scripts/harden.sh prod                                 # Apply hardening baseline
make monitoring                                          # Start Prometheus + Grafana
```

See [`DEPLOYMENT.md`](DEPLOYMENT.md) for the full walkthrough (reverse proxy,
TLS, backup scheduling, performance tuning, Kubernetes migration with Kompose).

### Branch Strategy

- Leaf repository active development branch: **`feature/official-hubs-01`**
- Management repo (`products/`) tracks the same branch via git submodule pointer.
- Releases are tagged from the release branch (see `release.json` and
  `CHANGELOG.md`).

## License

This repository is dual-licensed:

- **GNU Affero General Public License v3.0 or later** (AGPL-3.0-or-later)
- **Apache License, Version 2.0**

You may choose either license at your option. The full text of both licenses is
included in the [`LICENSE`](LICENSE) file. The SPDX expression is:

```
AGPL-3.0-or-later OR Apache-2.0
```

See [`NOTICE`](NOTICE) for copyright, trademark and third-party component
notices. The bundled third-party images (PostgreSQL, Redis, Prometheus, Grafana,
Nginx, Ubuntu, Python, Node) retain their upstream licenses.

```
Repository:  git@atomgit.com:openairymax/docker.git
Branch:      feature/official-hubs-01
SPDX:        AGPL-3.0-or-later OR Apache-2.0
```

Copyright (c) 2025-2026 SPHARX Ltd. All Rights Reserved.
