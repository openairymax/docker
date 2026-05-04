# Docker Secrets 部署指南
# 版本: 1.0.0 (BAN-43 合规)
# 最后更新: 2026-05-04

## 概述

本文档说明如何使用 Docker Secrets 安全管理 AgentOS 生产环境的敏感信息，符合 **BAN-43** 规范（禁止Docker Compose/K8s配置中硬编码密钥）。

## 为什么需要 Docker Secrets？

### ❌ 不安全的方式（已修复）
```bash
# docker-compose.yml 中硬编码密码（违反 BAN-43）
environment:
  POSTGRES_PASSWORD: staging_password_2024_change_me  # ❌ 明文暴露
```

### ✅ 安全的方式（当前实现）
```bash
# 使用环境变量引用
environment:
  POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}  # ✅ 从 .env 或 secrets 注入
```

## 部署方式

### 方式1: .env 文件（开发/Staging环境）

#### 步骤：
1. 复制模板文件：
   ```bash
   cp .env.example .env
   cp .env.staging.example .env.staging
   ```

2. 编辑 `.env` 文件，填入真实密钥：
   ```bash
   # 生成强随机JWT密钥（至少32字符）
   openssl rand -base64 64 | tr -d '\n' > /tmp/jwt_secret.txt
   echo "GATEWAY_JWT_SECRET=$(cat /tmp/jwt_secret.txt)" >> .env

   # 生成数据库密码
   openssl rand -base64 32 | tr -d '\n' > /tmp/pg_password.txt
   echo "POSTGRES_PASSWORD=$(cat /tmp/pg_password.txt)" >> .env

   # 生成Redis密码
   openssl rand -base64 32 | tr -d '\n' > /tmp/redis_password.txt
   echo "REDIS_PASSWORD=$(cat /tmp/redis_password.txt)" >> .env

   # 生成Grafana密码
   echo "GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 16 | tr -d '\n')" >> .env
   ```

3. 确保 `.env` 在 `.gitignore` 中：
   ```gitignore
   .env
   .env.production
   .env.staging
   ```

4. 启动服务：
   ```bash
   docker compose --env-file .env up -d
   ```

---

### 方式2: Docker Secrets（生产环境推荐）

#### 前置条件：
- Docker Swarm 模式已初始化：`docker swarm init`
- 或 Kubernetes 集群已配置

#### 步骤：

1. **创建 Secrets**：
   ```bash
   # JWT Secret
   echo "$(openssl rand -base64 64)" | docker secret create agentos_jwt_secret -

   # PostgreSQL Password
   echo "$(openssl rand -base64 32)" | docker secret create agentos_postgres_password -

   # Redis Password
   echo "$(openssl rand -base64 32)" | docker secret create agentos_redis_password -

   # Grafana Admin Password
   echo "$(openssl rand -base64 16)" | docker secret create agentos_grafana_password -

   # OpenLab Secret Key
   echo "$(openssl rand -hex 32)" | docker secret create agentos_openlab_secret -

   # LLM API Key（可选）
   echo "sk-your-actual-api-key" | docker secret create agentos_llm_api_key -
   ```

2. **验证 Secrets 已创建**：
   ```bash
   docker secret ls
   # 输出应包含：
   # agentos_jwt_secret
   # agentos_postgres_password
   # agentos_redis_password
   # agentos_grafana_password
   # agentos_openlab_secret
   # agentos_llm_api_key
   ```

3. **修改 docker-compose.prod.yml 使用 Secrets**：
   ```yaml
   version: '3.8'

   services:
     postgres:
       environment:
         POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password
       secrets:
         - postgres_password

     redis:
       command: >
         redis-server
         --requirepass $(cat /run/secrets/redis_password)
         ...
       secrets:
         - redis_password

     gateway:
       environment:
         GATEWAY_JWT_SECRET_FILE: /run/secrets/jwt_secret
       secrets:
         - jwt_secret

     grafana:
       environment:
         GF_SECURITY_ADMIN_PASSWORD_FILE: /run/secrets/grafana_password
       secrets:
         - grafana_password

     openlab:
       environment:
         OPENLAB_SECRET_KEY_FILE: /run/secrets/openlab_secret
       secrets:
         - openlab_secret

   secrets:
     jwt_secret:
       external: true
       name: agentos_jwt_secret
     postgres_password:
       external: true
       name: agentos_postgres_password
     redis_password:
       external: true
       name: agentos_redis_password
     grafana_password:
       external: true
       name: agentos_grafana_password
     openlab_secret:
       external: true
       name: agentos_openlab_secret
   ```

4. **部署 Stack**：
   ```bash
   docker stack deploy -c docker-compose.prod.yml agentos
   ```

---

### 方式3: Kubernetes Secrets（K8s环境）

#### 步骤：

1. **创建 Kubernetes Secret**：
   ```bash
   kubectl create secret generic agentos-secrets \
     --from-literal=jwt_secret="$(openssl rand -base64 64)" \
     --from-literal=postgres_password="$(openssl rand -base64 32)" \
     --from-literal=redis_password="$(openssl rand -base64 32)" \
     --from-literal=grafana_password="$(openssl rand -base64 16)" \
     --from-literal=openlab_secret="$(openssl rand -hex 32)"
   ```

2. **在 Deployment 中引用**：
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: gateway
   spec:
     template:
       spec:
         containers:
           - name: gateway
             envFrom:
               - secretRef:
                   name: agentos-secrets
             volumeMounts:
               - name: secrets
                 mountPath: /run/secrets
                 readOnly: true
         volumes:
           - name: secrets
             secret:
               secretName: agentos-secrets
   ```

---

## 密钥轮换策略

### 定期轮换（建议90天）

1. **生成新密钥**：
   ```bash
   # 新JWT密钥
   echo "$(openssl rand -base64 64)" | docker secret create agentos_jwt_secret_v2 -

   # 更新service
   docker service update --secret-add source=agentos_jwt_secret_v2,target=jwt_secret agentos_gateway
   docker service update --secret-rm agentos_jwt_secret agentos_gateway
   ```

2. **清理旧密钥**：
   ```bash
   docker secret rm agentos_jwt_secret
   ```

---

## 安全最佳实践

### ✅ 必须遵守：

1. **永远不要将 `.env` 文件提交到版本控制**
   - 已在 `.gitignore` 中排除
   
2. **使用强随机密码**
   - 最小长度：32字符
   - 包含大小写字母+数字+特殊字符
   - 使用 `openssl rand` 或 `pwgen` 生成

3. **最小权限原则**
   - 仅授权的服务可访问对应的secret
   - 定期审计secret访问日志

4. **备份和恢复**
   - 导出secrets列表：`docker secret ls`
   - 备份加密存储的密钥材料

5. **监控和告警**
   - 监控未授权的secret访问尝试
   - 设置secret生命周期策略

### ❌ 禁止事项：

- ❌ 在docker-compose.yml中硬编码密码
- ❌ 将密码提交到Git仓库
- • 使用弱密码（如 "password", "123456"）
- • 在日志中打印敏感信息
- • 多个环境共享同一套密码

---

## 故障排查

### 问题1: Secret不存在
```bash
Error: secret 'agentos_jwt_secret' not found
```
**解决方案**: 确保已创建secret：`docker secret ls`

### 问题2: 权限不足
```bash
Error: permission denied while trying to connect to the Docker daemon socket
```
**解决方案**: 使用sudo或添加用户到docker组

### 问题3: 环境变量未生效
```bash
Environment variable GATEWAY_JWT_SECRET is not set
```
**解决方案**: 
1. 检查`.env`文件是否存在
2. 验证变量名拼写
3. 运行`docker compose config`查看实际配置

---

## 相关文档

- [BAN-43 规范](../DocsClosed/工程规范化标准手册09.md#114-docker与密钥安全)
- [Docker官方文档](https://docs.docker.com/engine/swarm/secrets/)
- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)

---

**版本历史**:

| 版本 | 日期 | 变更说明 |
|------|------|---------|
| 1.0.0 | 2026-05-04 | 初始版本，支持3种部署方式 |

---

© 2026 SPHARX Ltd. All Rights Reserved.
