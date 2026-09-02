<div align="center">

# Airymax Docker 部署

> Airymax AI 智能体运行时平台的官方容器化部署方案 —— 多阶段、安全加固的
> OCI 镜像，配合 Docker Compose 编排覆盖开发、预发布与生产环境。

**语言:** [English](README.md) | 简体中文

Powered by OpenAirymax

[![Version](https://img.shields.io/badge/version-0.1.1-5a6b7e)](https://atomgit.com/openairymax/docker/releases)
[![License](https://img.shields.io/badge/license-AGPL--3.0+Apache--2.0-4a90d9)](LICENSE)
[![Branch](https://img.shields.io/badge/branch-feature%2Fofficial--hubs--01-6f42c1)](https://atomgit.com/openairymax/docker)

[![Docker](https://img.shields.io/badge/Docker-24.0+-2496ED?logo=docker\&logoColor=white)](https://www.docker.com)
[![Compose](https://img.shields.io/badge/Docker%20Compose-2.20+-2496ED?logo=docker\&logoColor=white)](https://docs.docker.com/compose/)
[![Ubuntu](https://img.shields.io/badge/base%20image-ubuntu%2024.04-E95420?logo=ubuntu\&logoColor=white)](https://ubuntu.com)

</div>

---

## 概述

**Docker 模块**是 Airymax 平台的官方容器化部署层。它将 AgentRT 运行时、守护进程服务、
网关、OpenLab 与桌面 Web 前端打包为可重现的 OCI 镜像，并提供三套 Docker Compose 编排
（开发 / 预发布 / 生产），将它们与 PostgreSQL、Redis 及完整的 Prometheus + Grafana +
AlertManager 可观测性栈串联起来。它是
[`products/`](https://atomgit.com/openairymax/products) 管理仓下三个叶子仓之一，
另两个为 `desktop`（个人客户端）和 `memoryrovol`（商业记忆提供者）。

本模块提供 **四个多阶段 Dockerfile** —— `Dockerfile.kernel`、`Dockerfile.daemon`、
`Dockerfile.openlab` 和 `Dockerfile.desktop` —— 每个产出多个命名构建 target
（builder / runtime / gateway / debug / production / development）。Compose 编排将这些镜像组装为
完整的运行时拓扑：一个微内核容器前置十三个 Supervisor 管理的守护进程
（`a2a_d`、`agent_d`、`channel_d`、`cupolas_d`、`hook_d`、`llm_d`、`market_d`、
`mem_d`、`monit_d`、`notify_d`、`sched_d`、`think_d`、`tool_d`）与一个三协议
（HTTP / WebSocket / stdio）网关，由 PostgreSQL 提供关系存储、Redis 提供 IPC 缓存、
会话与限流。

部署在所有生产服务上实现了 CIS Docker Benchmark 1.5+ 对齐的安全基线：非 root
`agentrt:1000` 用户、`read_only` 文件系统、`config/seccomp-profile.json` 系统调用白名单、
`cap_drop: ALL`、`no-new-privileges: true`、结构化 JSON 日志轮转、每个服务的分层 HEALTHCHECK
探针，以及 `${VAR:?error}` 强制校验使栈在缺失任何密钥时立即失败。CI 每次构建均运行 Trivy 扫描。
本模块面向需要在生产环境中运行、扩容和观测 Airymax 的 DevOps 工程师、SRE 与企业运维人员。

## 目录结构

```
docker/
├── Dockerfile.kernel          # Kernel 镜像（ubuntu:24.04 多阶段）
├── Dockerfile.daemon          # Daemon / Gateway 镜像（supervisord 管理）
├── Dockerfile.openlab         # OpenLab 镜像（python:3.12-slim + nginx）
├── Dockerfile.desktop         # Desktop Web 镜像（node:20 + nginx:1.27）
│
├── docker-compose.yml         # 开发栈
├── docker-compose.staging.yml # 预发布栈（与生产 1:1 镜像）
├── docker-compose.prod.yml    # 生产栈（安全加固）
│
├── .env.example                       # 开发环境变量模板
├── .env.staging.example               # 预发布环境变量模板
├── .env.production.example            # 生产环境变量模板（含密钥生成命令）
│
├── config/                            # 运行时配置
│   ├── gateway.yaml                   #   网关：协议、限流、JWT、上游
│   ├── seccomp-profile.json           #   seccomp 系统调用白名单（CIS 5.7）
│   ├── supervisor/                    #   supervisord 主配置 + 各守护进程 conf.d/
│   ├── nginx/                         #   反向代理 + desktop/openlab 静态配置
│   │   ├── openlab.conf  desktop.conf  agentrt-proxy.conf
│   └── logging/                       #   Fluent Bit 日志聚合模板
│       └── fluent-bit.conf
│
├── monitoring/                        # 可观测性栈
│   ├── prometheus.yml                 #   抓取配置（kernel/gateway/postgres/redis）
│   ├── alertmanager.yml               #   告警路由（PagerDuty/Slack/Email）
│   ├── rules/                         #   告警规则文件
│   │   ├── kernel.yml  agentrt_alerts.yml
│   └── grafana/                       #   自动 provisioning 的数据源与仪表盘
│
├── scripts/                           # 运维工具
│   ├── quick-start.sh                 #   交互式启动器（环境检查 + 菜单）
│   ├── install.sh                     #   一键安装脚本
│   ├── healthcheck.sh                 #   多层健康探针（text/JSON）
│   ├── backup.sh                      #   备份 / 恢复 / 校验 / 列表（GPG + SHA256）
│   ├── generate-secrets.sh            #   强随机密钥生成器
│   ├── harden.sh                      #   安全加固执行器
│   ├── openlab-entrypoint.sh          #   OpenLab 容器入口
│   └── verify-build.sh                #   构建后验证
│
├── secrets/                           # Docker Secrets 模板与指南
├── tests/integration/                 # 集成测试套件（test_services.py）
├── .github/                           # CI 工作流（构建 → 扫描 → 测试 → 发布）
├── .trivy.yml                         # Trivy 漏洞扫描策略
├── .hadolint.yaml                     # Dockerfile linter 配置
├── .dockerignore
│
├── DEPLOYMENT.md                      # 分步部署指引
├── CHANGELOG.md                       # 发布历史
├── release.json                       # 发布元数据
├── LICENSE                            # AGPL-3.0 + Apache-2.0 双许可证全文
├── NOTICE                             # 版权与第三方声明
├── README.md                          # 英文版
└── README_zh.md                       # 本文件
```

## 功能 / 组件

### 镜像与构建 Target

| 镜像 | Dockerfile | Target | 端口 | 用途 |
|------|-----------|--------|------|------|
| `spharx/agentrt-kernel` | `Dockerfile.kernel` | `builder`、`runtime`、`debug` | `18080/tcp`（IPC API）· `9090/tcp`（指标） | 微内核核心 —— IPC、内存、任务、时间 |
| `spharx/agentrt-daemon` / `agentrt-gateway` | `Dockerfile.daemon` | `builder`、`runtime`、`gateway`、`debug` | `18789/tcp`（API）· `18790/tcp`（管理） | Supervisor 管理的守护进程与三协议网关（HTTP / WebSocket / stdio） |
| `spharx/agentrt-openlab` | `Dockerfile.openlab` | `backend-builder`、`production`、`development` | `8000/tcp`（API）· `80/tcp` / `443/tcp`（Web）· `5173/tcp`（开发） | OpenLab 交互平台 —— Python 后端 + Nginx 静态 |
| `spharx/agentrt-desktop` | `Dockerfile.desktop` | `builder`、`production` | `80/tcp` | 桌面客户端的静态 Web 构建，由 Nginx 服务 |

### Compose 编排的守护进程服务

`docker-compose.yml`（开发）启动 kernel 加上十三个 Supervisor 管理的守护进程与网关：

| 服务 | 角色 |
|------|------|
| `kernel` | 微内核 IPC 核心，所有守护进程的唯一上游 |
| `a2a_d` | A2A 智能体通信守护进程 |
| `agent_d` | Agent 生命周期守护进程 |
| `channel_d` | 通道服务守护进程 |
| `cupolas_d` | 安全穹顶守护进程（权限/净化/审计） |
| `hook_d` | Hook 注册与触发守护进程 |
| `llm_d` | LLM 服务守护进程 |
| `market_d` | 工具市场守护进程 |
| `mem_d` | 记忆存储守护进程 |
| `monit_d` | 监控与可观测守护进程 |
| `notify_d` | 通知推送守护进程 |
| `sched_d` | 任务调度守护进程 |
| `think_d` | 双思考守护进程 |
| `tool_d` | 工具执行守护进程 |
| `gateway` | 前置 kernel 的 HTTP/WS/stdio 网关（target: `gateway`） |

### 端口规划

| 端口 | 服务 | 暴露 | 用途 |
|------|------|------|------|
| **18789** | Gateway API | 公开 | 统一外部 API 入口 |
| **18790** | Gateway Admin | 受限 | 管理 API（IP 受限） |
| 18080 | Kernel IPC | 内部 | Syscall API（仅网关） |
| 9090 | Kernel Metrics | 内部 | Prometheus `/metrics` |
| 5432 | PostgreSQL | 内部 | 关系存储（HeapStore 慢速层） |
| 6379 | Redis | 内部 | IPC 缓存、会话、限流 |
| 9091 | Prometheus | 受限 | 监控 UI（生产仅 VPN） |
| 3000 | Grafana | 受限 | 仪表盘（生产仅 VPN） |

### 技术栈

| 层次 | 技术 |
|------|------|
| 基础镜像 | `ubuntu:24.04`（kernel/daemon）、`python:3.12-slim`（openlab）、`node:20-slim`（desktop builder）、`nginx:1.27-alpine`（静态服务） |
| 构建工具链 | GCC 12、CMake 3.22 + Ninja、Python 3.12 venv、npm ci |
| 进程管理 | `supervisord` 用于 daemon/gateway 容器 |
| 编排 | Docker Compose v2（开发 / 预发布 / 生产） |
| 数据存储 | PostgreSQL 15-alpine、Redis 7-alpine |
| 可观测性 | Prometheus v2.45、Grafana 10.2、AlertManager |
| 日志 | JSON-file 驱动 + 轮转 + 可选 Fluent Bit sidecar |
| 安全 | seccomp、cap_drop ALL、只读 FS、非 root `agentrt:1000` |
| CI/CD | GitHub Actions（Buildx 多架构 + Trivy 扫描 + SARIF） |

### 安全基线（CIS Docker Benchmark 1.5+）

| CIS | 控制项 | 实现方式 |
|-----|--------|----------|
| 4.1 | 受信任基础镜像 | 官方 `ubuntu:24.04`、`python:3.12-slim`、`nginx:1.27-alpine` |
| 4.6 | HEALTHCHECK | 每个服务均有分层健康探针 |
| 5.4 | Rootless 容器 | `USER agentrt:1000`（UID/GID 1000，shell `/sbin/nologin`） |
| 5.7 | seccomp | `config/seccomp-profile.json` 白名单 |
| 5.9 | 只读文件系统 | 生产服务 `read_only: true` |
| 5.10 | 禁用 suid/sgid | `cap_drop: ALL` |
| 5.11 | 禁止获取新权限 | `no-new-privileges:true` |
| 5.26 | 能力白名单 | 仅 `cap_add: NET_BIND_SERVICE` |
| 5.29 | 日志驱动配置 | `json-file` + `max-size` + `max-file` 轮转 |

密钥绝不硬编码：生产清单使用 `${VAR:?error}` 在缺失时立即失败，`secrets/` 提供 Docker Secrets 工作流文档。
CI 在每次构建时运行 Trivy 扫描。

## 上游依赖

```
   ┌─────────────────────────────────┐
   │  AgentRT 运行时（sdk/agentrt）  │
   │  ecosystem/manager 配置         │
   └────────────────┬────────────────┘
                    │ 构建时 COPY 源码
                    ▼
   ┌─────────────────────────────────┐
   │     products/docker（镜像）     │
   │   Dockerfile.kernel             │
   │   Dockerfile.daemon             │
   │   Dockerfile.openlab            │
   │   Dockerfile.desktop            │
   └────────────────┬────────────────┘
                    │ docker compose up
                    ▼
   ┌─────────────────────────────────┐
   │  运维人员 / 企业部署            │
   │  （开发 / 预发布 / 生产）       │
   └─────────────────────────────────┘
```

- **`AgentRT/` 运行时源码树** —— kernel + daemons + gateway + OpenLab 源码，
  在镜像构建期被 `COPY` 进各 builder 阶段。构建上下文为伞仓根目录（`context: ..`），
  因此四个 Dockerfile 直接读取运行时源码。
- **`ecosystem/manager/` 配置默认值** —— 通过 `config/`（gateway.yaml、supervisor conf.d、
  nginx、Fluent Bit）消费并烘焙进运行时镜像。
- **`products/desktop` 源码** —— 被 `Dockerfile.desktop` 消费以构建 Web 前端镜像
  （纯 Vite 构建，不含 Tauri 原生外壳）。构建时 `COPY Desktop/` 并执行 `npm ci && npm run build`。
- **第三方 OCI 镜像** —— `ubuntu:24.04`、`python:3.12-slim`、`node:20-slim`、
  `nginx:1.27-alpine`、`postgres:15-alpine`、`redis:7-alpine`、`prom/prometheus`、
  `grafana/grafana`、`prom/alertmanager`。这些镜像保留其上游许可证。

## 下游消费者

- **运维 / 企业部署** —— 通过三套 Compose 清单在开发、预发布与生产环境中运行产出镜像。
  支持栈扩容（如 `docker compose up --scale kernel=3`）。
- **`products/desktop` 终端用户** —— 可让桌面客户端与本地启动的 `docker compose` 栈并行运行，
    作为网关后端（默认 `localhost:18789`）。
- **Airymax Hub 伞仓** —— 在 `feature/official-hubs-01` 分支上将本叶子仓作为 git 子模块固定，
  用于协同发布。发布从 release 分支打 tag（见 `release.json` 与 `CHANGELOG.md`）。
- **可选：`products/memoryrovol`** —— 商业记忆提供者可在构建期通过
  `-DAGENTRT_WITH_MEMORYROVOL=ON` 链接进 AgentRT 运行时，再由本模块容器化，
  在商业 EULA 下解锁 L3/L4 记忆能力。

## 构建 / 安装

### 前置条件

| 组件 | 最低 | 推荐（生产） |
|------|------|--------------|
| 操作系统 | Ubuntu 20.04+ / CentOS 8+ | Ubuntu 22.04 LTS（加固版） |
| CPU | 4 核 | 16+ 核 |
| 内存 | 8 GB | 32+ GB |
| 磁盘 | 50 GB SSD | 500+ GB SSD |
| Docker Engine | 20.10.0 | 24.0.0 |
| Docker Compose | 2.0.0（V2 插件） | 2.20.0 |
| 工具 | `git`、`curl`、`jq`、`openssl`、`make` | 同左 |

```bash
# Ubuntu 安装示例
sudo apt-get update && sudo apt-get install -y \
    docker.io docker-compose-v2 git curl jq openssl make

# 让当前用户无需 sudo 即可运行 Docker
sudo usermod -aG docker "$USER" && newgrp docker
```

### 快速开始（开发环境）

```bash
# 1. 克隆（叶子仓位于 feature/official-hubs-01 分支）
git clone -b feature/official-hubs-01 git@atomgit.com:openairymax/docker.git
cd docker

# 2. 配置环境（默认指向 localhost:18789）
cp .env.example .env

# 3. 启动开发栈（kernel + 6 个守护进程 + 网关）
docker compose -f docker-compose.yml --env-file .env up -d

# 4. 验证健康
./scripts/healthcheck.sh
# 期望输出：Overall Status: HEALTHY
```

其他启动方式：

```bash
./scripts/quick-start.sh dev   # 交互式启动器
make dev                       # Makefile 快捷命令
make dev-full                  # 同上，但同时启动监控 profile
```

### 预发布环境部署

`docker-compose.staging.yml` 是生产栈的 1:1 镜像，使用独立数据卷，默认开启监控 profile。
用于发布前验证、压力测试与回归测试。

```bash
cp .env.staging.example .env.staging
# 编辑 .env.staging —— 填入强随机密钥
docker compose -f docker-compose.staging.yml --env-file .env.staging up -d
./scripts/healthcheck.sh --env staging --json
```

### 生产环境部署

```bash
# 1. 创建生产 env 文件（必填密钥通过 ${VAR:?} 强制校验）
cp .env.production.example .env.production
chmod 600 .env.production

# 2. 生成强随机密钥
./scripts/generate-secrets.sh            # 写入 POSTGRES_PASSWORD、REDIS_PASSWORD、
                                          # GATEWAY_JWT_SECRET、OPENLAB_SECRET_KEY 等

# 3. 启动加固后的生产栈
docker compose -f docker-compose.prod.yml \
    --env-file .env.production up -d

# 4. 验证
./scripts/healthcheck.sh --env prod --json

# 5. （可选）创建首次备份
./scripts/backup.sh backup --env prod
```

### 验证

```bash
# 网关健康
curl -fsS http://localhost:18789/api/v1/health

# Kernel IPC（仅开发；生产为内部端口）
curl -fsS http://localhost:18080/api/v1/health

# 数据库
docker compose exec postgres pg_isready -U agentrt

# Redis
docker compose exec redis sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli ping'
```

### 常用操作

```bash
docker compose -f docker-compose.yml ps                 # 列出服务
docker compose logs -f gateway kernel                    # 跟随日志
docker compose exec kernel bash                          # 进入容器
docker compose -f docker-compose.prod.yml up -d --scale kernel=3   # 扩容 kernel
docker stats --no-stream                                 # 资源快照
./scripts/backup.sh list                                 # 列出备份
./scripts/backup.sh restore <file>.tar.gz --env prod     # 灾难恢复
./scripts/harden.sh prod                                 # 应用加固基线
make monitoring                                          # 启动 Prometheus + Grafana
```

完整指引（反向代理、TLS、备份调度、性能调优、Kompose 迁移 Kubernetes）详见
[`DEPLOYMENT.md`](DEPLOYMENT.md)。

### 分支策略

- 叶子仓活跃开发分支：**`feature/official-hubs-01`**
- 管理仓（`products/`）通过 git 子模块指针跟踪同一分支。
- 发布从 release 分支打 tag（见 `release.json` 与 `CHANGELOG.md`）。

## 许可证

本仓库采用双许可证：

- **GNU Affero General Public License v3.0 or later**（AGPL-3.0-or-later）
- **Apache License, Version 2.0**

可任选其一适用。两份许可证的完整文本均见 [`LICENSE`](LICENSE) 文件。SPDX 表达式为：

```
AGPL-3.0-or-later OR Apache-2.0
```

版权、商标与第三方组件声明详见 [`NOTICE`](NOTICE)。捆绑的第三方镜像
（PostgreSQL、Redis、Prometheus、Grafana、Nginx、Ubuntu、Python、Node）保留其上游许可证。

```
仓库:    git@atomgit.com:openairymax/docker.git
分支:    feature/official-hubs-01
SPDX:    AGPL-3.0-or-later OR Apache-2.0
```

Copyright (c) 2025-2026 SPHARX Ltd. All Rights Reserved.
