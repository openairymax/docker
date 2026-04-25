# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0] - 2026-04-23

### Added

- **Staging Environment** (`docker-compose.staging.yml`)
  - 1:1 replica of production environment
  - Isolated data volumes
  - Full monitoring stack enabled by default
  - Use case: Pre-release validation, stress testing, regression testing

- **Makefile Commands** (30+ commands)
  - `make dev/prod/staging` - One-command environment startup
  - `make logs/status/healthcheck` - Quick diagnostics
  - `make build/clean/security` - Build management
  - `make shell-*` - Quick container shell access
  - `make backup/restore/list-backups` - Backup operations

- **Quick Start Script** (`scripts/quick-start.sh`)
  - Interactive CLI with menu
  - Automatic environment check (Docker version, memory, disk)
  - Color output with Logo display
  - Auto-display access addresses after startup

- **CI/CD Pipeline** (GitHub Actions)
  - Multi-stage: Build → Security Scan → Integration Test → Benchmark → Publish
  - Trivy vulnerability scanning with SARIF report upload
  - Docker Buildx multi-platform build support
  - Slack notification integration

- **Nginx Reverse Proxy Configuration** (`config/nginx/agentos-proxy.conf`)
  - SSL/TLS termination + HTTP/2 support
  - WebSocket proxy + CORS handling
  - Grafana sub-path proxy + Basic Auth
  - Security headers (HSTS/XSS-Protection/CSP)

- **Log Aggregation Solution** (`config/logging/fluent-bit.conf`)
  - Support for Loki/Elasticsearch/CloudWatch output
  - Kubernetes metadata injection
  - Structured JSON log parsing

- **Trivy Security Scanning Configuration** (`.trivy.yml`)
  - CVE whitelist management
  - Dockerfile best practices check
  - Image security baseline check

- **Enhanced .dockerignore**
  - CI/CD files exclusion
  - Security report files exclusion
  - Backup files exclusion

### Changed

- **README.md** - Updated to v3.0.0 with comprehensive documentation
- **Alert Rules** - Version bumped to 3.0.0 with enhanced thresholds

### Security

- CIS Docker Benchmark compliance reinforced
- Capability whitelist (`cap_drop: ALL`)
- Security profile (`seccomp-profile.json`)
- No privilege escalation (`no-new-privileges:true`)

---

## [2.0.1] - 2026-04-15

### Fixed

- Port configuration consistency between documentation and code

---

## [2.0.0] - 2026-04-06

### Added

- **Gateway Service** - Three-protocol gateway (HTTP/WS/stdio) as sole external entry point
- **Dual-layer Network Isolation** - Frontend/backend network separation, zero-trust architecture
- **Named Volume Management** - Easy operation identification and backup
- **Prometheus Alert Rules** - 5 groups, 15+ production-grade alert rules
- **Production Environment Variable Template** - `.env.production.example`

### Security

- CIS Docker Benchmark compliance (10+ controls)
- Mandatory password validation (`${VAR:?❌ ERROR}` syntax)
- Non-root user execution (`USER agentos:1000`)
- Port minimization for production

---

## [1.0.0] - 2026-03-01

### Added

- Initial Docker module with basic Compose configuration
- Kernel, Gateway, PostgreSQL, Redis services
- Basic health check and backup scripts
