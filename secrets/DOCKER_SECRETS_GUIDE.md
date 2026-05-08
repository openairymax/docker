# =============================================================================
# AgentOS Docker Secrets 部署指南
# 版本: 1.0.0 (团队E - 第09轮次)
# 最后更新: 2026-05-05
# BAN合规: BAN-43, BAN-57
# =============================================================================

## 概述

本指南描述如何使用 Docker Swarm Secrets 管理 AgentOS 的敏感信息（密码、API 密钥、JWT 密钥等），符合 BAN-43（禁止硬编码密钥）和 BAN-57（CORS 安全配置）规范。

### 为什么需要 Docker Secrets？

| 问题 | 无 Secrets | 有 Secrets |
|------|-----------|------------|
| 密码存储 | 明文写入 .env 文件 | 加密存储，仅运行时解密 |
| 进程可见 | `docker inspect` 暴露环境变量 | 内存文件系统，不可见 |
| 备份安全 | 备份包含明文密码 | 备份不包含 secrets |
| 轮换 | 需重启所有容器 | Swarm rolling update |
| 审计 | 无法追踪访问 | Swarm 日志记录访问 |

## 架构

```
┌─────────────────────────────────────────────────┐
│                Docker Swarm Manager              │
│  ┌─────────────────────────────────────────┐    │
│  │         Raft Consensus Log              │    │
│  │  ┌───────┐ ┌───────┐ ┌───────┐         │    │
│  │  │Secret1│ │Secret2│ │Secret3│ ...     │    │
│  │  └───────┘ └───────┘ └───────┘         │    │
│  └─────────────────────────────────────────┘    │
│                      │                           │
│                      ▼                           │
│  ┌─────────────────────────────────────────┐    │
│  │         Worker Node                      │    │
│  │  Container ──▶ /run/secrets/<name>       │    │
│  │              (tmpfs, 内存文件系统)         │    │
│  └─────────────────────────────────────────┘    │
└─────────────────────────────────────────────────┘
```

## 快速开始

### 1. 初始化 Docker Swarm

```bash
# 单节点 Swarm（开发/测试）
docker swarm init

# 多节点 Swarm（生产）
docker swarm init --advertise-addr <MANAGER_IP>
docker swarm join --token <WORKER_TOKEN> <MANAGER_IP>:2377
```

### 2. 创建 Secrets

```bash
# 方法1: 从文件创建（推荐）
openssl rand -base64 48 | tr -d '\n=' > /tmp/jwt_secret.txt
docker secret create agentos_jwt_secret /tmp/jwt_secret.txt
shred -u /tmp/jwt_secret.txt

# 方法2: 从标准输入
openssl rand -base64 32 | docker secret create agentos_postgres_password -

# 方法3: 从环境变量（不推荐，可能在历史记录中暴露）
echo "$MY_PASSWORD" | docker secret create agentos_redis_password -
```

### 3. 创建所有必需的 Secrets

```bash
#!/bin/bash
# secrets/create-all-secrets.sh
set -euo pipefail

echo "Creating AgentOS Docker Secrets..."

# JWT 密钥 (256-bit, base64url)
openssl rand -base64 48 | tr -d '\n=' | docker secret create agentos_jwt_secret_v1 -

# PostgreSQL 密码 (32字符)
openssl rand -base64 32 | tr -d '\n' | docker secret create agentos_postgres_password_v1 -

# Redis 密码 (64字符 hex)
openssl rand -hex 32 | docker secret create agentos_redis_password_v1 -

# Grafana 管理员密码
openssl rand -base64 24 | tr -d '\n' | docker secret create agentos_grafana_password_v1 -

# OpenLab 密钥 (Django SECRET_KEY)
python3 -c "import secrets; print(secrets.token_urlsafe(50))" | \
  docker secret create agentos_openlab_secret_key_v1 -

echo "All secrets created successfully."
docker secret ls
```

### 4. 部署 Stack

```bash
# 开发环境
docker stack deploy -c docker-compose.yml agentos-dev

# 预发布环境
docker stack deploy -c docker-compose.staging.yml agentos-staging

# 生产环境
docker stack deploy -c docker-compose.prod.yml agentos-prod
```

## Secrets 清单

| Secret 名称                        | 用途                  | 生成命令                                    | 轮换周期 |
|------------------------------------|-----------------------|---------------------------------------------|----------|
| `agentos_jwt_secret_v1`            | JWT 签名密钥          | `openssl rand -base64 48 \| tr -d '\n='`    | 90 天    |
| `agentos_postgres_password_v1`     | PostgreSQL 数据库密码 | `openssl rand -base64 32 \| tr -d '\n'`     | 90 天    |
| `agentos_redis_password_v1`        | Redis 缓存密码        | `openssl rand -hex 32`                      | 90 天    |
| `agentos_grafana_password_v1`      | Grafana 管理员密码    | `openssl rand -base64 24 \| tr -d '\n'`     | 90 天    |
| `agentos_openlab_secret_key_v1`    | OpenLab 应用密钥      | `python3 -c "import secrets; print(secrets.token_urlsafe(50))"` | 180 天 |

## Compose 文件中使用 Secrets

### 开发环境示例 (`docker-compose.yml`)

```yaml
services:
  gateway:
    secrets:
      - source: agentos_jwt_secret_v1
        target: /run/secrets/jwt_secret
        mode: 0400
    environment:
      - GATEWAY_JWT_SECRET_FILE=/run/secrets/jwt_secret

  postgres:
    secrets:
      - source: agentos_postgres_password_v1
        target: /run/secrets/postgres_password
    environment:
      - POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password

  redis:
    secrets:
      - source: agentos_redis_password_v1
        target: /run/secrets/redis_password
    command: >
      redis-server
      --requirepass $$(cat /run/secrets/redis_password)
```

## 密钥轮换流程

### Step 1: 创建新版本密钥

```bash
openssl rand -base64 48 | tr -d '\n=' | docker secret create agentos_jwt_secret_v2 -
```

### Step 2: 更新 Compose 文件

```yaml
secrets:
  - source: agentos_jwt_secret_v2  # 新版本
    target: /run/secrets/jwt_secret
```

### Step 3: 滚动更新

```bash
docker service update --secret-rm agentos_jwt_secret_v1 \
  --secret-add agentos_jwt_secret_v2 agentos-prod_gateway
```

### Step 4: 移除旧密钥（确认无问题后）

```bash
docker secret rm agentos_jwt_secret_v1
```

## 安全检查清单

- [ ] 已初始化 Docker Swarm
- [ ] 使用 `openssl rand` 生成所有密钥（无人工选择）
- [ ] 所有 Secret 文件在创建后已用 `shred` 安全删除
- [ ] Compose 文件中无硬编码密码（BAN-43）
- [ ] `.env.production` 引用 Secret 而非明文密码
- [ ] Secret 权限设置为 `0400`（仅 owner 只读）
- [ ] 已设置密钥轮换提醒（90 天）
- [ ] Swarm Manager 节点已加固（防火墙、SSH 密钥认证）
- [ ] 备份策略明确排除 `/run/secrets/`

## 从 .env 迁移到 Secrets

| 迁移前 (.env)                | 迁移后 (Secrets)                    |
|------------------------------|-------------------------------------|
| `JWT_SECRET=my_secret`       | `DOCKER-SECRET:agentos_jwt_secret`  |
| `POSTGRES_PASSWORD=mypass`   | `DOCKER-SECRET:agentos_postgres_password` |
| `REDIS_PASSWORD=myredis`     | `DOCKER-SECRET:agentos_redis_password` |
| `GRAFANA_PASSWORD=mygrafana` | `DOCKER-SECRET:agentos_grafana_password` |

## 故障排除

### 问题: `secret not found`

```bash
docker secret ls  # 确认 secret 存在
docker service inspect <service> --format '{{json .Spec.TaskTemplate.ContainerSpec.Secrets}}'
```

### 问题: `permission denied`

```bash
# 检查 secret 权限
docker exec <container> ls -la /run/secrets/
```

### 问题: 容器启动后无法读取 Secret

Secret 挂载到 `/run/secrets/<name>`，需要应用代码支持 `_FILE` 后缀的环境变量：

```python
import os
def get_secret(name, default=None):
    file_path = os.environ.get(f"{name}_FILE")
    if file_path and os.path.exists(file_path):
        with open(file_path, 'r') as f:
            return f.read().strip()
    return os.environ.get(name, default)
```

## 参考

- [Docker Swarm Secrets 官方文档](https://docs.docker.com/engine/swarm/secrets/)
- [CIS Docker Benchmark v1.6.0](https://www.cisecurity.org/benchmark/docker)
- AgentOS BAN-43: 禁止硬编码密钥规范
- AgentOS BAN-57: CORS 安全配置规范
