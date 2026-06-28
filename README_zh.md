<div align="center">

# AgentOS Docker 部署

Powered by OpenAirymax

> 基于 CIS Docker Benchmark 合规的生产级容器化架构

中文 | [English](README.md)

[![AtomGit](https://atomgit.com/openairymax/docker/star/badge.svg)](https://atomgit.com/openairymax/docker)

[![Version](https://img.shields.io/badge/version-0.1.0-5a6b7e)](https://atomgit.com/openairymax/docker)
[![License](https://img.shields.io/badge/license-Proprietary-4a90d9)](https://atomgit.com/openairymax/docker/blob/main/LICENSE)

[![Docker](https://img.shields.io/badge/Docker-24.0+-2496ED?logo=docker\&logoColor=white)](https://www.docker.com)
[![Compose](https://img.shields.io/badge/Docker%20Compose-2.20+-2496ED?logo=docker\&logoColor=white)](https://docs.docker.com/compose/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04-E95420?logo=ubuntu\&logoColor=white)](https://ubuntu.com)

</div>

***

## 相关仓库

| 仓库                | 链接                                                                         |
| ----------------- | -------------------------------------------------------------------------- |
| AgentOS 核心源码      | [atomgit.com/openairymax/agentos](https://atomgit.com/openairymax/agentos) |
| 文档模块              | [atomgit.com/openairymax/docs](https://atomgit.com/openairymax/docs)       |
| **Docker 部署（当前）** | [atomgit.com/openairymax/docker](https://atomgit.com/openairymax/docker)   |
| 桌面客户端             | [atomgit.com/openairymax/desktop](https://atomgit.com/openairymax/desktop) |

## 📖 目录

- [1. 项目概述](#1-项目概述)
- [2. 系统架构](#2-系统架构)
- [3. 前置要求](#3-前置要求)
- [4. 快速开始](#4-快速开始)
- [5. 服务详解](#5-服务详解)
- [6. 安全最佳实践](#6-安全最佳实践)
- [7. 运维手册](#7-运维手册)
- [8. 监控与告警](#8-监控与告警)
- [9. 扩展指南](#9-扩展指南)
- [10. 故障排查](#10-故障排查)
- [11. 附录](#11-附录)

## 1. 项目概述

### 1.1 什么是 AgentOS Docker？

AgentOS Docker 是 **AgentOS 智能体操作系统** 的官方容器化部署方案，提供从开发环境到生产环境的**一站式容器编排解决方案**。

### 核心特性

| 特性类别        | 具体能力                                      | 实现方式                                         |
| ----------- | ----------------------------------------- | -------------------------------------------- |
| 🔒 **安全加固** | CIS Benchmark 合规、非 root 用户、seccomp、只读文件系统 | Dockerfile 安全配置 + Compose security\_opt      |
| 🛡️ **高可用** | 多实例部署、健康检查、自动重启、优雅降级                      | restart\_policy + healthcheck + replicas     |
| 📊 **可观测性** | Prometheus 指标采集 + Grafana 可视化 + 结构化日志     | monitoring/ 目录 + JSON 日志驱动                   |
| ⚡ **性能优化**  | 连接池调优、内存管理、缓存策略、资源限制                      | deploy.resources + 数据库参数调优                   |
| 🔄 **数据安全** | ACID 事务保证、AOF/RDB 持久化、自动化备份               | PostgreSQL WAL + Redis AOF + backup.sh 脚本    |
| 🚀 **快速部署** | 一键启动、环境变量模板、多目标构建                         | docker-compose.yml + .env.production.example |

### 关键版本信息

| 组件              | 版本        | 端口                           | 说明                 |
| --------------- | --------- | ---------------------------- | ------------------ |
| AgentOS Kernel  | v2.0.0    | 18080 (IPC) / 9090 (Metrics) | 微内核核心              |
| AgentOS Gateway | v2.0.0    | 18789 (API) / 18790 (Admin)  | 三协议网关              |
| Python SDK      | v0.1.0    | 默认连接 18789                   | `agentos` Python 包 |
| PostgreSQL      | 15-alpine | 5432 (内网)                    | 关系型数据库             |
| Redis           | 7-alpine  | 6379 (内网)                    | 内存缓存               |
| Prometheus      | v2.45.0   | 9091 (偏移)                    | 监控引擎               |
| Grafana         | 10.2.0    | 3000                         | 可视化平台              |

## 2. 系统架构

### 2.1 整体架构图

#### 开发环境拓扑 (Development)

```
                         ┌──────────────────────────────────┐
                         │        开发者机器 (Developer)      │
                         └─────────────┬────────────────────┘
                                       │ HTTP/WS :18789
                                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│                        agentos-frontend (172.29.0.0/16)              │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────────────────┐  │
│  │   OpenLab   │    │   Gateway    │    │       Grafana           │  │
│  │  :5173/:8000│◄──►│ :18789/:18790│◄──►│         :3000           │  │
│  │  [optional] │    │  (统一入口)   │    │    [monitoring]         │  │
│  └─────────────┘    └──────┬───────┘    └─────────────────────────┘  │
│                             │                                        │
└─────────────────────────────┼────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│                        agentos-backend (172.28.0.0/16)               │
│  ┌─────────────┐    ┌──────────┐    ┌──────────┐    ┌──────────────┐ │
│  │   Kernel    │    │PostgreSQL│    │  Redis   │    │  Prometheus  │ │
│  │:18080/:9090 │◄──►│  :5432   │◄──►│  :6379   │◄──►│    :9091     │ │
│  │(微内核核心)   │    │ (ACID)   │    │ (LRU)    │    │[monitoring]  │ │
│  └─────────────┘    └──────────┘    └──────────┘    └──────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

#### 生产环境拓扑 (Production)

```
                    Internet / CDN
                         │ HTTPS :443
                         ▼
              ┌─────────────────────┐
              │   Load Balancer     │
              │  (Nginx/HAProxy)    │
              └──────────┬──────────┘
                         │ HTTP :18789
                         ▼
┌────────────────────────────────────────────────────────────────────┐
│                   DMZ / Frontend Network (172.31.0.0/16)           │
│                                                                    │
│  ┌─────────────────────┐    ┌──────────────────────────────────┐   │
│  │   Gateway Cluster   │    │        Grafana                   │   │
│  │   :18789 (LB)       │◄──►│        :3000 (VPN Only)          │   │
│  │   [N instances]     │    │        [monitoring profile]      │   │
│  └──────────┬──────────┘    └──────────────────────────────────┘   │
│             │                                                      │
└─────────────┼──────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   Internal / Backend Network (172.30.0.0/16)        │
│                                                                     │
│  ┌──────────────┐    ┌────────────┐    ┌────────────────────────┐   │
│  │Kernel Cluster│    │ PostgreSQL │    │ Redis Cluster          │   │
│  │:18080 (内部) │◄──►│  HA (主从)  │◄──►│ Sentinel (高可用)       │   │
│  │[M instances] │    │  :5432     │    │ :6379                  │   │
│  └──────────────┘    └────────────┘    └────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 端口规划表

| 端口        | 服务            | 协议      | 环境         | 用途            | 安全级别 |
| --------- | ------------- | ------- | ---------- | ------------- | ---- |
| **18789** | Gateway       | HTTP/WS | Dev + Prod | **统一 API 入口** | 公开   |
| **18790** | Gateway Admin | HTTP    | Dev + Prod | 网关管理 API      | 受限   |
| 3000      | Grafana       | HTTP    | Dev + Prod | 监控可视化         | 受限   |
| **18080** | Kernel IPC    | HTTP    | 内网         | 内核 API        | 内部   |
| 5432      | PostgreSQL    | TCP     | 内网         | 数据库连接         | 内部   |
| 6379      | Redis         | TCP     | 内网         | 缓存连接          | 内部   |



## 3. 前置要求

### 3.1 系统要求

| 组件                 | 最低配置          | 推荐配置 (开发)        | 推荐配置 (生产)                   |
| ------------------ | ------------- | ---------------- | --------------------------- |
| **操作系统**           | Ubuntu 20.04+ | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS (hardened) |
| **CPU**            | 4 核心          | 8 核心             | 16+ 核心                      |
| **内存**             | 8 GB RAM      | 16 GB RAM        | 32+ GB RAM                  |
| **磁盘**             | 50 GB SSD     | 100 GB NVMe SSD  | 500GB+ SSD                  |
| **Docker**         | ≥ 20.10.0     | ≥ 24.0.0         | ≥ 24.0.0                    |
| **Docker Compose** | ≥ 2.0.0       | ≥ 2.20.0         | ≥ 2.20.0                    |

### 3.2 安装依赖

```bash
sudo apt-get update && sudo apt-get install -y \
    docker.io docker-compose-v2 git curl jq openssl make
```



## 4. 快速开始

### 4.1 开发环境一键启动

```bash
# 方式一: 使用快速启动脚本 (推荐)
./docker/scripts/quick-start.sh dev

# 方式二: 使用 Make 命令
make dev

# 方式三: 使用 Docker Compose
docker compose -f docker/docker-compose.yml up -d

# 启动完整栈 (含监控)
make dev-full
# 或
docker compose -f docker/docker-compose.yml --profile monitoring up -d

# 验证部署状态
make healthcheck
make status
```

### 4.2 生产环境部署

```bash
# 步骤 1: 创建生产环境变量文件
cp docker/.env.production.example docker/.env.production
vim docker/.env.production  # 编辑所有密码和密钥!

# 步骤 2: 生成强随机密码
openssl rand -base64 32 | tr -d '\n' | head -c 32; echo  # PostgreSQL
openssl rand -hex 32                                      # Redis
openssl rand -base64 48 | tr -d '\n=' | head -c 43; echo  # JWT

# 步骤 3: 启动生产环境
docker compose -f docker/docker-compose.prod.yml \
    --env-file docker/.env.production \
    up -d

# 步骤 4: 验证健康状态
./docker/scripts/healthcheck.sh --env prod --json
```


## 5. 服务详解

### 5.1 Kernel 内核服务

**镜像**: `spharx/agentos-kernel:2.0.0`\
**端口**: 18080 (IPC API) + 9090 (Prometheus Metrics)

Kernel 是 AgentOS 的**微内核核心**，实现四大原子机制：

| 机制         | 功能描述                |
| ---------- | ------------------- |
| **IPC**    | 进程间通信，统一 Syscall 接口 |
| **Memory** | 内存分配与回收，虚拟内存管理      |
| **Task**   | 任务调度，优先级队列，时间片轮转    |
| **Time**   | 定时器，时钟同步，超时机制       |

### 5.2 Gateway 网关服务

**镜像**: `spharx/agentos-gateway:2.0.0`\
**端口**: 18789 (API) + 18790 (Admin)

Gateway 是**唯一对外入口**，实现三协议网关：

| 协议            | 端点路径         | 用途      |
| ------------- | ------------ | ------- |
| **HTTP REST** | `/api/v1/*`  | 同步请求-响应 |
| **WebSocket** | `/ws`        | 全双工实时通信 |
| **stdio**     | stdin/stdout | 管道通信    |

### 5.3 PostgreSQL 数据库

**镜像**: `postgres:15-alpine`\
**端口**: 5432 (仅内网访问)\
**用途**: HeapStore 慢速存储层、事务性数据、复杂查询

### 5.4 Redis 缓存服务

**镜像**: `redis:7-alpine`\
**端口**: 6379 (仅内网访问)\
**用途**: IPC 高速通道、权限缓存、会话存储、Rate Limiting

### 5.5 Prometheus 监控系统

**镜像**: `prom/prometheus:v2.45.0`\
**端口**: 9091\
**启动**: `--profile monitoring`

### 5.6 Grafana 可视化平台

**镜像**: `grafana/grafana:10.2.0`\
**端口**: 3000\
**启动**: `--profile monitoring`


## 6. 安全最佳实践

### 6.1 CIS Docker Benchmark 合规

| CIS 编号   | 要求             | 实现方式                   | 状态 |
| -------- | -------------- | ---------------------- | -- |
| **4.1**  | 使用受信任的基础镜像     | ubuntu:22.04 (官方)      | ✅  |
| **5.4**  | 使用 rootless 容器 | USER agentos:1000      | ✅  |
| **5.7**  | 配置 seccomp     | seccomp-profile.json   | ✅  |
| **5.9**  | 只读文件系统         | read\_only: true       | ✅  |
| **5.11** | 禁止获取新权限        | no-new-privileges:true | ✅  |

### 6.2 密钥管理策略

```bash
# PostgreSQL 密码
POSTGRES_PW=$(openssl rand -base64 32 | tr -d '\n' | head -c 32; echo)

# JWT Secret
JWT_SECRET=$(openssl rand -base64 48 | tr -d '\n=' | head -c 43; echo)

# 保护 .env 文件
chmod 600 docker/.env.production
```


## 7. 运维手册

### 7.1 日常运维命令

```bash
# 启动所有服务
docker compose -f docker/docker-compose.yml up -d

# 停止所有服务
docker compose -f docker/docker-compose.yml down --timeout 60

# 查看日志
docker compose logs -f gateway kernel

# 进入容器调试
docker compose exec kernel bash

# 查看资源使用
docker stats
```

### 7.2 备份恢复

```bash
# 完整备份
./docker/scripts/backup.sh backup --env prod

# 列出备份
./docker/scripts/backup.sh list

# 恢复备份
./docker/scripts/backup.sh restore <BACKUP_FILE> --env prod
```


## 8. 监控与告警

### 8.1 核心指标

| 指标名称                               | 服务         | 说明           | 告警阈值            |
| ---------------------------------- | ---------- | ------------ | --------------- |
| `up`                               | 所有         | 服务存活状态       | == 0 (critical) |
| `http_request_duration_seconds`    | Gateway    | 请求延迟分布       | P99 > 2s        |
| `agentos_syscall_duration_seconds` | Kernel     | Syscall 执行时间 | P99 > 1s        |
| `pg_stat_activity_count`           | PostgreSQL | 活跃连接数        | > 90%           |

### 8.2 告警级别

| 级别              | 响应时间   | 通知渠道            | 影响范围 |
| --------------- | ------ | --------------- | ---- |
| **Critical** 🔴 | < 5 分钟 | PagerDuty + SMS | 服务宕机 |
| **Warning** 🟡  | < 4 小时 | Slack + Email   | 性能下降 |
| **Info** 🔵     | 下个工作日  | 仅 Slack         | 容量规划 |


## 9. 扩展指南

### 9.1 水平扩展

```bash
# 扩展 Kernel 到 3 个实例
docker compose -f docker/docker-compose.prod.yml up -d --scale kernel=3

# 扩展 Gateway 到 2 个实例
docker compose -f docker/docker-compose.prod.yml up -d --scale gateway=2
```

### 9.2 Kubernetes 迁移

```bash
# 使用 Kompose 转换
kompose convert -f docker/docker-compose.prod.yml -o k8s/

# 应用到集群
kubectl apply -f k8s/
```


## 10. 故障排查

### 10.1 常见问题

#### 容器无法启动 (Exit Code 137)

**原因**: OOM Killer

**解决方案**:

```bash
# 增加 memory limit
deploy:
  resources:
    limits:
      memory: 8G  # 从 4G 增加到 8G
```

#### Gateway 返回 502 Bad Gateway

**原因**: Kernel 服务不可达

**排查步骤**:

```bash
docker ps | grep kernel
docker compose exec gateway curl -f http://kernel:18080/api/v1/health
```


## 11. 附录

### 11.1 文件结构说明

```
docker/
├── README.md                          # 📖 本文档
├── Dockerfile.kernel                  # 🔨 内核镜像构建
├── Dockerfile.daemon                  # 🔨 守护进程镜像构建
├── docker-compose.yml                 # 🐳 开发环境编排
├── docker-compose.prod.yml            # 🐳 生产环境编排
├── .env.production.example            # 🔐 生产环境变量模板
├── config/                           # ⚙️ 配置文件目录
├── scripts/                          # 🛠️ 运维脚本
└── monitoring/                       # 📊 监控栈配置
```


## 📞 支持与反馈

- **文档问题**: 提交 Issue 到 [AtomGit Issues](https://atomgit.com/openairymax/docker/issues)
- **安全问题**: 发送邮件至 🔒 <security@spharx.cn>
- **运维支持**: 联系 DevOps 团队 <ops@spharx.cn>


## 📄 许可证

本项目采用 **Proprietary License** (专有许可证)。详见 [LICENSE](../LICENSE) 文件。

***

<p align="center">
  <strong>Made with ❤️ by SPHARX Platform Team</strong><br>
  <em>Last Updated: 2026-04-23 | Version: 0.1.0</em>
</p>
