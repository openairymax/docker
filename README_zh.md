<div align="center">

# Airymax Docker 部署

> Airymax AI Agent Runtime 平台的官方容器化部署——多阶段、安全加固的 OCI 镜像，
> 配套面向开发、预发布与生产的 Docker Compose 编排。

**语言：** [English](README.md) | 简体中文

Powered by OpenAirymax

[![License](https://img.shields.io/badge/license-AGPL--3.0+Apache--2.0-4a90d9)](LICENSE)
[![Branch](https://img.shields.io/badge/branch-main-6f42c1)](https://atomgit.com/openairymax/docker)

[![Docker](https://img.shields.io/badge/Docker-24.0+-2496ED?logo=docker&logoColor=white)](https://www.docker.com)
[![Compose](https://img.shields.io/badge/Docker%20Compose-2.20+-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![Ubuntu](https://img.shields.io/badge/base%20image-ubuntu%2024.04-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com)

</div>

---

## 概述

**Docker 模块**是 Airymax 平台的官方容器化部署层。它将 AgentRT 运行时、守护
进程服务、网关、OpenLab 与桌面端 Web 前端打包为可复现的 OCI 镜像，并提供三份
Docker Compose 编排清单（开发 / 预发布 / 生产）。预发布与生产环境在此基础上
加入 PostgreSQL、Redis 以及 Prometheus + Grafana 可观测性栈；`monitoring/`
目录另外提供 Alertmanager 告警路由配置模板，供按需部署使用。本仓库是
[`products/`](https://atomgit.com/openairymax/products) 管理仓之下的三个叶子仓
之一，与 `desktop`（个人客户端）、`memoryrovol`（商业记忆提供方）并列。

本模块提供 **四个多阶段 Dockerfile**——`Dockerfile.kernel`、
`Dockerfile.daemon`、`Dockerfile.openlab` 与 `Dockerfile.desktop`，各自产出
一个或多个命名构建目标（builder / runtime / gateway / debug / production /
development）。开发编排组装出完整的运行时拓扑：一个微内核容器、十三个由
`supervisord` 托管的守护进程容器（`a2a_d`、`agent_d`、`channel_d`、
`cupolas_d`、`hook_d`、`llm_d`、`market_d`、`mem_d`、`monit_d`、`notify_d`、
`sched_d`、`think_d`、`tool_d`），以及一个三协议（HTTP / WebSocket / stdio）
网关。预发布与生产编排在此基础上扩展 PostgreSQL（关系存储）、Redis（缓存、
会话与限流）、Prometheus + Grafana（监控），以及 OpenLab 与桌面端 Web 前端。

生产编排为所有服务实施对齐 CIS Docker Benchmark 的安全基线：
`no-new-privileges:true`、`read_only` 只读文件系统、`cap_drop: ALL`、作用于
kernel 容器的 seccomp 系统调用白名单（`config/seccomp-profile.json`）、非 root
运行用户（kernel 与守护进程为 `agentrt`，UID/GID 1000；OpenLab 为
`openlab`）、结构化 JSON 日志轮转，以及每个自研镜像内的 `HEALTHCHECK` 探针。
仓库同时内置 lint / 扫描策略文件（`.hadolint.yaml`、`.trivy.yml`），便于接入
外部镜像扫描器。本模块面向需要在生产环境运行并观测 Airymax 的 DevOps 工程师、
SRE 与企业运维人员。

## 目录结构

```
docker/
├── Dockerfile.kernel          # 内核镜像（ubuntu:24.04；builder/runtime/debug）
├── Dockerfile.daemon          # 守护进程 / 网关镜像（ubuntu:24.04，supervisord）
├── Dockerfile.openlab         # OpenLab 镜像（python:3.12-slim；backend-builder/
│                              #   production/development）
├── Dockerfile.desktop         # 桌面 Web 镜像（node:20-slim 构建器 +
│                              #   nginx:1.27-alpine 运行时）
│
├── docker-compose.yml         # 开发栈（kernel + 13 守护进程 + gateway）
├── docker-compose.staging.yml # 预发布栈（完整拓扑，默认启用监控）
├── docker-compose.prod.yml    # 生产栈（安全加固）
│
├── .env.example               # 开发环境模板
├── .env.staging.example       # 预发布环境模板
├── .env.production.example    # 生产环境模板
│
├── config/                    # 运行时配置（烧入镜像）
│   ├── gateway.yaml           #   网关：bind 0.0.0.0:18789、HTTP/WS/stdio、CORS
│   ├── seccomp-profile.json   #   seccomp 系统调用白名单（kernel 容器）
│   ├── supervisor/
│   │   └── supervisord.conf   #   supervisord 主配置
│   ├── nginx/                 #   反向代理与静态站点配置
│   │   ├── openlab.conf  desktop.conf  agentrt-proxy.conf
│   └── logging/
│       └── fluent-bit.conf    #   可选的 Fluent Bit 日志采集模板
│
├── monitoring/                # 可观测性配置
│   ├── prometheus.yml         #   抓取配置（kernel / gateway / prometheus）
│   ├── alertmanager.yml       #   Alertmanager 路由模板（webhook + SMTP）
│   ├── rules/                 #   告警规则（kernel.yml、agentrt_alerts.yml）
│   └── grafana/               #   预置数据源与仪表盘
│
├── scripts/                   # 运维工具
│   ├── quick-start.sh         #   交互式启动器（dev/staging/prod/stop/clean）
│   ├── install.sh             #   一键安装器
│   ├── healthcheck.sh         #   多服务健康探针（文本/JSON）
│   ├── backup.sh              #   备份 / 恢复 / 校验 / 列表 / 清理
│   ├── generate-secrets.sh    #   随机强密钥生成器（写入 secrets/*.txt）
│   ├── harden.sh              #   操作系统与服务加固套件
│   ├── openlab-entrypoint.sh  #   OpenLab 容器入口
│   └── verify-build.sh        #   构建后校验
│
├── secrets/                   # 生成的密钥文件（不入库）+ 使用指南
├── tests/                     # 集成测试套件（tests/integration/）
├── .github/                   # CI 工作流（许可证与清单校验）
├── .trivy.yml                 # Trivy 扫描策略（供外部扫描器集成）
├── .hadolint.yaml             # Dockerfile linter 配置
├── .dockerignore
│
├── DEPLOYMENT.md              # 分步部署指南
├── CHANGELOG.md               # 发布历史
├── release.json               # 发布元数据
├── LICENSE                    # AGPL-3.0 + Apache-2.0 双许可文本
├── NOTICE                     # 版权与第三方声明
├── README.md                  # 英文版
└── README_zh.md               # 本文件
```

## 功能 / 组件

### 镜像与构建目标

镜像遵循命名规则
`${DOCKER_REGISTRY:-spharx}/agentrt-<component>:${AGENTRT_VERSION:-0.1.1}`；
仓库与版本标签均可通过环境变量配置。

| 镜像 | Dockerfile | 构建目标 | 容器端口 | 用途 |
|------|-----------|---------|----------|------|
| `agentrt-kernel` | `Dockerfile.kernel` | `builder`、`runtime`、`debug` | `18080/tcp`（IPC API）· `9090/tcp`（指标） | 微内核核心——IPC、内存、任务、时间 |
| `agentrt-<name>_d` / `agentrt-gateway` | `Dockerfile.daemon` | `builder`、`runtime`、`gateway`、`debug` | `8080/tcp` · `8081/tcp`（EXPOSE） | 十三个 supervisord 托管的守护进程；`gateway` 目标承载三协议网关（HTTP / WebSocket / stdio，见 `config/gateway.yaml`） |
| `agentrt-openlab` | `Dockerfile.openlab` | `backend-builder`、`production`、`development` | `8000/tcp`（API）· `443/tcp`（Web，production）· `5173/tcp`（开发服务器，development） | OpenLab 交互平台——Python 后端 + Nginx 静态 |
| `agentrt-desktop` | `Dockerfile.desktop` | `builder`、`production` | `80/tcp` | 桌面客户端静态 Web 构建，由 Nginx 提供 |

> 说明：守护进程镜像 `EXPOSE` 的 8080/8081 面向 supervisord 托管的守护进程；
> 网关容器的监听端口由其配置决定（预发布/生产为 18789 API + 18790 管理），
> 并通过 `GATEWAY_PORT` / `GATEWAY_ADMIN_PORT` 映射到宿主机。

### Compose 编排的服务

`docker-compose.yml`（开发）启动内核、十三个守护进程容器与网关——共 15 个
服务：

| 服务 | 职责 |
|------|------|
| `kernel` | 微内核 IPC 核心，所有守护进程的唯一权威 |
| `a2a_d` | A2A 智能体通信守护进程 |
| `agent_d` | 智能体生命周期守护进程 |
| `channel_d` | 通道服务守护进程 |
| `cupolas_d` | 安全穹顶守护进程（权限 / 净化 / 审计） |
| `hook_d` | Hook 注册与触发守护进程 |
| `llm_d` | LLM 服务守护进程 |
| `market_d` | 工具市场守护进程 |
| `mem_d` | 记忆存储守护进程 |
| `monit_d` | 监控与可观测守护进程 |
| `notify_d` | 通知推送守护进程 |
| `sched_d` | 任务调度守护进程 |
| `think_d` | 双思考守护进程 |
| `tool_d` | 工具执行守护进程 |
| `gateway` | 面向内核的 HTTP/WS/stdio 网关（构建目标：`gateway`） |

预发布与生产编排额外加入 `postgres`、`redis`、`prometheus`、`grafana`、
`desktop`，以及 `openlab`（通过 `openlab` Compose profile 启用）。

### 端口规划

宿主机侧的暴露由环境变量控制，同一份清单即可适配开发与加固部署：

| 容器端口 | 服务 | 宿主机发布 | 用途 |
|----------|------|------------|------|
| 18789 | 网关 API（HTTP + WebSocket） | `${GATEWAY_PORT}`——开发回退 `8080`，预发布/生产回退 `18789`；`.env.example` 固定为 `18789` | 统一外部 API 入口 |
| 18790 | 网关管理 API | `${GATEWAY_ADMIN_PORT:-18790}`（预发布/生产） | 管理 API（限制来源 IP） |
| 8080 / 8081 | 守护进程（supervisord） | 不发布 | 内部守护进程 HTTP/状态 |
| 18080 | 内核 IPC API | 仅开发：`${KERNEL_IPC_PORT:-18080}`——预发布/生产不发布 | 系统调用 API（面向网关） |
| 9090 | 内核指标 | 不发布，网络内抓取 | Prometheus `/metrics` |
| 8000 | OpenLab API | `${OPENLAB_API_PORT:-8000}` | OpenLab 后端 |
| 443 / 5173 | OpenLab Web（production / development） | `${OPENLAB_WEB_PORT:-443}` | OpenLab 前端 |
| 80 | 桌面 Web（Nginx） | `${DESKTOP_PORT:-8080}`（生产） | 桌面客户端静态站点 |
| 5432 | PostgreSQL | 不发布 | 关系存储 |
| 6379 | Redis | 不发布 | 缓存、会话、限流 |
| 9090 | Prometheus | `127.0.0.1:${PROMETHEUS_PORT:-9091}`（生产） | 监控 UI / API，仅本地回环 |
| 3000 | Grafana | `${GRAFANA_PORT:-3000}`（生产） | 仪表盘 |

### 技术栈

| 层 | 技术 |
|----|------|
| 基础镜像 | `ubuntu:24.04`（kernel/daemon）、`python:3.12-slim`（openlab）、`node:20-slim`（desktop 构建器）、`nginx:1.27-alpine`（desktop 运行时） |
| 构建工具链 | GCC 12、CMake 3.28 + Ninja 1.11（`Dockerfile.kernel` 内固定）、Python 3.12 venv、`npm ci` |
| 进程托管 | 守护进程/网关容器使用 `supervisord` |
| 编排 | Docker Compose v2（开发 / 预发布 / 生产） |
| 数据存储 | `postgres:16-alpine`、`redis:7.2-alpine` |
| 可观测性 | `prom/prometheus:v2.50.0`、`grafana/grafana:10.3.0`；`monitoring/` 内含 Alertmanager 路由模板 |
| 日志 | `json-file` 驱动，按大小/数量轮转（`LOG_MAX_SIZE` / `LOG_MAX_FILE`） |
| 安全 | seccomp（kernel）、`cap_drop: ALL`、只读文件系统、`no-new-privileges`、非 root 运行用户 |
| CI | 许可证检查 + Dockerfile/Compose 清单校验（`.github/workflows/`） |

### 安全基线

生产编排对**全部**服务（`kernel`、`gateway`、`postgres`、`redis`、`openlab`、
`prometheus`、`grafana`、`desktop`）实施以下控制：

| 控制项 | 实现 |
|--------|------|
| 可信基础镜像 | 官方 `ubuntu:24.04`、`python:3.12-slim`、`node:20-slim`、`nginx:1.27-alpine` |
| HEALTHCHECK | 四个自研镜像均定义健康探针 |
| 非 root 运行 | 内核与守护进程以 `agentrt` 运行（UID/GID 1000，禁登录 shell）；OpenLab 以 `openlab` 运行 |
| seccomp | `config/seccomp-profile.json` 系统调用白名单，作用于 kernel 容器 |
| 只读文件系统 | 每个生产服务均 `read_only: true` |
| 能力裁剪 | `cap_drop: ALL`；仅在服务确需时保留最小 `cap_add` |
| 禁止提权 | 每个生产服务均 `no-new-privileges:true` |
| 日志驱动 | 每个服务 `json-file` + `max-size` / `max-file` 轮转 |

密钥绝不硬编码：每套环境通过 env 文件（`--env-file`）加载配置。
`scripts/generate-secrets.sh` 将强随机密钥写为 `secrets/` 下的 `600` 权限文件
（已加入 `.gitignore`），可直接填入 `.env.production`；`secrets/` 目录同时记录面向
Swarm 部署的可选 Docker Secrets 工作流——参见
[`secrets/README.md`](secrets/README.md)。

## 上游依赖

```
   ┌────────────────────────────────────────┐
   │    AgentRT 源码树（工作区根）           │
   │  kernel · daemons · gateway · openlab  │
   └───────────────────┬────────────────────┘
                       │ 构建期 COPY 源码
                       ▼
   ┌────────────────────────────────────────┐
   │        products/docker（镜像）          │
   │  kernel · daemon · openlab · desktop   │
   └───────────────────┬────────────────────┘
                       │ docker compose up
                       ▼
   ┌────────────────────────────────────────┐
   │         运维人员 / 企业                 │
   │      （开发、预发布、生产）             │
   └────────────────────────────────────────┘
```

- **AgentRT 运行时源码树**——kernel + daemons + gateway + OpenLab 源码，在镜像
  构建期 `COPY` 进各 builder 阶段。三份清单的构建上下文均为工作区根
  （`context: ../..`），因此四个 Dockerfile 直接读取运行时源码。
- **运行时配置**——`config/`（gateway.yaml、supervisord.conf、nginx、
  Fluent Bit）被复制进 runtime 阶段并烧入镜像。
- **`products/desktop` 源码**——由 `Dockerfile.desktop` 消费以构建 Web 前端
  镜像（纯 Vite 构建由 Nginx 提供；不含 Tauri 原生外壳）。
- **第三方 OCI 镜像**——`ubuntu:24.04`、`python:3.12-slim`、`node:20-slim`、
  `nginx:1.27-alpine`、`postgres:16-alpine`、`redis:7.2-alpine`、
  `prom/prometheus:v2.50.0`、`grafana/grafana:10.3.0`。它们保留各自的上游
  许可证。

## 下游消费者

- **运维人员 / 企业部署**——通过三份 Compose 清单在开发、预发布与生产运行产出
  的镜像。内核为有状态核心，随附 `KERNEL_REPLICAS=1`；无状态组件可按需通过
  Compose 扩容。
- **`products/desktop` 用户**——可将桌面客户端指向本地启动的 Compose 栈所发布
  的网关（宿主端口由 `GATEWAY_PORT` 控制）。
- **`products/` 管理仓**——以 git submodule 指针固定本仓库，统一协调发布。
  发布按 `release.json` 与 `CHANGELOG.md` 打标签。
- **可选：`products/memoryrovol`**——商业记忆提供方可在容器化之前，于构建期
  通过 `-DAIRY_WITH_MEMORYROVOL=ON` 与 `AIRY_MEMORY_BACKEND=memoryrovol` 接入
  AgentRT 运行时，解锁 SPHARX 商业 EULA 下的商业记忆能力。

## 构建 / 安装

### 环境要求

| 组件 | 最低 | 推荐（生产） |
|------|------|--------------|
| 操作系统 | Ubuntu 20.04+ / CentOS 8+ | Ubuntu 22.04 LTS（加固） |
| CPU | 4 核 | 16+ 核 |
| 内存 | 8 GB | 32+ GB |
| 磁盘 | 50 GB SSD | 500+ GB SSD |
| Docker Engine | 20.10.0 | 24.0.0 |
| Docker Compose | 2.0.0（V2 插件） | 2.20.0 |
| 工具 | `git`、`curl`、`jq`、`openssl` | 同左 |

```bash
# Ubuntu 安装示例
sudo apt-get update && sudo apt-get install -y \
    docker.io docker-compose-v2 git curl jq openssl

# 允许当前用户免 sudo 使用 Docker
sudo usermod -aG docker "$USER" && newgrp docker
```

### 快速开始（开发环境）

```bash
# 1. 克隆
git clone https://atomgit.com/openairymax/docker.git
cd docker

# 2. 配置环境
cp .env.example .env

# 3. 启动开发栈（kernel + 13 守护进程 + gateway）
docker compose -f docker-compose.yml --env-file .env up -d

# 4. 健康检查
./scripts/healthcheck.sh
# 预期输出：Overall Status: HEALTHY
```

使用随附的 `.env.example` 时，网关 API 发布于 `localhost:18789`
（`GATEWAY_PORT`），内核 IPC API 发布于 `localhost:18080`
（`KERNEL_IPC_PORT`）。

替代启动方式：

```bash
./scripts/quick-start.sh dev   # 交互式启动器（环境检查 + 菜单）
```

### 预发布（staging）部署

`docker-compose.staging.yml` 与生产拓扑一致，使用独立数据卷并默认启用监控，
用于发布前验证、浸泡测试与回归测试。

```bash
cp .env.staging.example .env.staging
# 编辑 .env.staging——填入强密钥
docker compose -f docker-compose.staging.yml --env-file .env.staging up -d
./scripts/healthcheck.sh --json
```

### 生产部署

```bash
# 1. 创建生产环境文件
cp .env.production.example .env.production
chmod 600 .env.production

# 2. 生成强随机密钥——在 secrets/ 下写入 600 权限文件
#   （postgres_password.txt、redis_password.txt、jwt_secret.txt、
#   grafana_password.txt，以及可选的 LLM API key 文件）。将值复制进
#   .env.production。
./scripts/generate-secrets.sh

# 3. 启动加固的生产栈
docker compose -f docker-compose.prod.yml \
    --env-file .env.production up -d

# 4. 校验
./scripts/healthcheck.sh --json

# 5.（可选）创建首个备份
./scripts/backup.sh backup --env prod
```

### 验证

```bash
# 网关健康（宿主端口 = ${GATEWAY_PORT}；使用随附模板时为 18789）
curl -fsS http://localhost:18789/api/v1/health

# 内核 IPC（仅开发——预发布/生产不发布）
curl -fsS http://localhost:18080/api/v1/health

# 数据库
docker compose -f docker-compose.prod.yml exec postgres pg_isready -U agentrt

# Redis
docker compose -f docker-compose.prod.yml exec redis \
    sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli ping'
```

### 常用操作

```bash
docker compose -f docker-compose.yml ps                # 列出服务
docker compose logs -f gateway kernel                  # 跟踪日志
docker compose exec kernel bash                        # 进入容器
docker stats --no-stream                               # 资源快照
./scripts/healthcheck.sh --json --service gateway      # 探测单个服务
./scripts/backup.sh list                               # 列出备份
./scripts/backup.sh restore <file>.tar.gz --env prod   # 灾难恢复
./scripts/harden.sh verify                             # 审计加固状态
./scripts/harden.sh all                                # 应用完整加固基线
./scripts/quick-start.sh stop                          # 停止运行中的栈
```

完整部署指南（反向代理、TLS、备份计划、性能调优）参见
[`DEPLOYMENT.md`](DEPLOYMENT.md)。

### 分支策略

- 活跃开发分支：**`main`**
- `products/` 管理仓通过 git submodule 指针跟踪本仓库。
- 发布按 `release.json` 与 `CHANGELOG.md` 打标签。

## 许可证

本仓库采用双许可：

- **GNU Affero 通用公共许可证 v3.0 或更新版本**（AGPL-3.0-or-later）
- **Apache 许可证 2.0 版**

您可任选其一使用。两份许可证的完整文本见 [`LICENSE`](LICENSE) 文件。SPDX
表达式为：

```
AGPL-3.0-or-later OR Apache-2.0
```

版权、商标与第三方组件声明见 [`NOTICE`](NOTICE)。随附的第三方镜像
（PostgreSQL、Redis、Prometheus、Grafana、Nginx、Ubuntu、Python、Node）保留
其各自的上游许可证。可选的 `memoryrovol` 记忆提供方以 SPHARX 商业 EULA 单独
分发，不在本仓库许可覆盖范围内。

```
仓库：    https://atomgit.com/openairymax/docker.git
分支：    main
SPDX：    AGPL-3.0-or-later OR Apache-2.0
```

Copyright (c) 2025-2026 SPHARX Ltd. All Rights Reserved.
