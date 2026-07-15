# AgentRT Docker 部署指南

**版本**: 0.1.0  
**最后更新**: 2026-04-23

---

## 📋 目录

1. [环境要求](#环境要求)
2. [快速开始](#快速开始)
3. [生产环境部署](#生产环境部署)
4. [监控与告警](#监控与告警)
5. [备份与恢复](#备份与恢复)
6. [故障排查](#故障排查)
7. [安全加固](#安全加固)
8. [性能调优](#性能调优)

---

## 🔧 环境要求

### 系统要求

| 组件 | 最低配置 | 推荐配置 |
|------|----------|----------|
| CPU | 2 核心 | 4+ 核心 |
| 内存 | 4 GB | 8+ GB |
| 磁盘 | 20 GB | 50+ GB SSD |
| 操作系统 | Linux / macOS / Windows (WSL2) | Ubuntu 22.04+ / CentOS 8+ |

### 软件依赖

- Docker 20.10+
- Docker Compose V2.20+
- Git 2.30+ (用于克隆)

### 验证环境

```bash
# 运行环境检查
./docker/scripts/quick-start.sh --check
```

---

## 🚀 快速开始

### 方式一：一键安装 (推荐)

```bash
# 下载并运行安装脚本
curl -fsSL https://raw.githubusercontent.com/spharx/agentrt/main/docker/scripts/install.sh | bash

# 或手动下载后运行
wget https://raw.githubusercontent.com/spharx/agentrt/main/docker/scripts/install.sh
chmod +x install.sh
./install.sh
```

### 方式二：使用 Make

```bash
# 克隆仓库
git clone https://github.com/spharx/agentrt.git
cd agentrt

# 启动开发环境
make dev
```

### 方式三：手动部署

```bash
# 1. 克隆仓库
git clone https://github.com/spharx/agentrt.git
cd agentrt/docker

# 2. 配置环境变量
cp .env.example .env
vim .env  # 修改默认密码

# 3. 启动服务
docker compose up -d

# 4. 验证部署
docker compose ps
```

### 验证部署

```bash
# 运行健康检查
./scripts/healthcheck.sh

# 或
make healthcheck
```

---

## 🏭 生产环境部署

### 1. 准备生产环境

```bash
# 复制生产环境模板
cp .env.production.example .env.production
```

### 2. 生成强密码

```bash
# JWT 密钥 (64 字节)
openssl rand -base64 64

# 数据库密码 (32 字节)
openssl rand -base64 32

# Redis 密码 (32 字节)
openssl rand -base64 32

# Grafana 管理员密码
openssl rand -base64 24
```

### 3. 配置环境变量

编辑 `.env.production`:

```bash
# 必填项 - 强密码
GATEWAY_JWT_SECRET=<your-64-byte-secret>
POSTGRES_PASSWORD=<your-32-byte-password>
REDIS_PASSWORD=<your-32-byte-password>
GRAFANA_ADMIN_PASSWORD=<your-24-byte-password>

# 网络配置
DOMAIN=api.yourcompany.com
SSL_CERT_PATH=/etc/ssl/certs/your-cert.pem
SSL_KEY_PATH=/etc/ssl/private/your-key.pem
```

### 4. 部署生产服务

```bash
# 启动生产环境
docker compose -f docker-compose.prod.yml \
  --env-file .env.production up -d

# 验证服务状态
docker compose -f docker-compose.prod.yml ps
```

### 5. 配置反向代理

```bash
# 使用提供的 Nginx 配置
sudo cp config/nginx/agentrt-proxy.conf /etc/nginx/conf.d/
sudo cp config/nginx/agentrt-proxy.conf /etc/nginx/sites-enabled/

# 替换 SSL 证书路径
sudo vim /etc/nginx/conf.d/agentrt-proxy.conf

# 测试配置
sudo nginx -t

# 重载 Nginx
sudo systemctl reload nginx
```

---

## 📊 监控与告警

### 启动监控栈

```bash
# 启动 Prometheus + Grafana + AlertManager
make monitoring

# 或
docker compose --profile monitoring up -d
```

### 访问监控面板

| 服务 | URL | 默认凭据 |
|------|-----|----------|
| Prometheus | http://localhost:9091 | 无 |
| Grafana | http://localhost:3000 | admin / &lt;见.env中GRAFANA_ADMIN_PASSWORD&gt; |
| AlertManager | http://localhost:9093 | 无 |

### 预置仪表盘

- [AgentRT 核心监控](monitoring/grafana/dashboards/agentrt_core.json) - QPS/延迟/成功率/资源使用
- [PostgreSQL 数据库](monitoring/grafana/dashboards/postgresql_monitor.json) - TPS/缓存命中/慢查询
- [Redis 缓存](monitoring/grafana/dashboards/redis_monitor.json) - 命中率/内存/键空间

### 告警规则

告警规则定义在 `monitoring/rules/agentrt_alerts.yml`，包含：

- **服务可用性** (Critical)
- **性能指标** (Warning)
- **资源使用** (Warning/Info)
- **数据库健康** (Critical/Warning)
- **缓存健康** (Critical/Warning)

### 配置告警通知

编辑 `monitoring/alertmanager.yml`:

```yaml
receivers:
  - name: 'slack-warnings'
    slack_configs:
      - channel: '#agentrt-alerts'
        send_resolved: true
        title: '[{{ .Status | toUpper }}] {{ .CommonAnnotations.summary }}'
```

---

## 💾 备份与恢复

### 创建备份

```bash
# 全量备份
./scripts/backup.sh backup

# 备份到指定目录
./scripts/backup.sh backup --output /path/to/backup

# GPG 加密备份
./scripts/backup.sh backup --encrypt --recipient your@email.com
```

### 列出备份

```bash
./scripts/backup.sh list
```

### 恢复备份

```bash
# 从备份恢复
./scripts/backup.sh restore /path/to/backup.tar.gz
```

### 自动备份 (Cron)

```bash
# 编辑 crontab
crontab -e

# 添加每日凌晨 2 点备份
0 2 * * * /path/to/docker/scripts/backup.sh backup --output /backup/agentrt
```

---

## 🔍 故障排查

### 常见问题

#### 1. 容器启动失败

```bash
# 查看容器日志
docker logs agentrt-kernel-dev
docker logs agentrt-gateway-dev

# 检查容器状态
docker compose ps
```

#### 2. 数据库连接失败

```bash
# 验证 PostgreSQL 健康
docker exec agentrt-postgres-dev pg_isready -U agentrt

# 检查连接数
docker exec agentrt-postgres-dev psql -U agentrt -c "SELECT count(*) FROM pg_stat_activity;"
```

#### 3. Redis 连接失败

```bash
# 测试 Redis 连接（使用REDISCLI_AUTH避免密码泄露）
docker exec agentrt-redis-dev sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli ping'
```

#### 4. 端口冲突

```bash
# 检查端口占用
sudo lsof -i :18789
sudo netstat -tlnp | grep 18789

# 修改端口
vim .env  # 修改 GATEWAY_PORT 等配置
```

### 诊断命令

```bash
# 查看所有容器资源使用
docker stats

# 查看网络配置
docker network inspect agentrt_backend

# 查看卷列表
docker volume ls | grep agentrt

# 运行健康检查
./scripts/healthcheck.sh --json
```

---

## 🔒 安全加固

### 自动加固

```bash
# 运行安全加固脚本
./scripts/harden.sh prod
```

### 手动加固

#### 1. 启用 AppArmor/SELinux

```bash
# Ubuntu AppArmor
sudo apt install apparmor-utils
sudo aa-enforce docker-default

# CentOS SELinux
sudo setenforce 1
```

#### 2. 限制容器能力

```yaml
# docker-compose.yml
services:
  kernel:
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    security_opt:
      - no-new-privileges:true
    read_only: true
```

#### 3. 启用 seccomp

```yaml
services:
  kernel:
    security_opt:
      - seccomp:./config/seccomp-profile.json
```

#### 4. 漏洞扫描

```bash
# 安装 Trivy
brew install aquasecurity/trivy/trivy

# 扫描镜像
trivy image spharx/agentrt-kernel:0.1.0

# 扫描文件系统
trivy fs --severity CRITICAL,HIGH .
```

---

## ⚡ 性能调优

### PostgreSQL 调优

```sql
-- 查看当前配置
SHOW shared_buffers;
SHOW effective_cache_size;
SHOW work_mem;

-- 推荐配置 (8GB 内存)
ALTER SYSTEM SET shared_buffers = '2GB';
ALTER SYSTEM SET effective_cache_size = '6GB';
ALTER SYSTEM SET work_mem = '64MB';
ALTER SYSTEM SET maintenance_work_mem = '512MB';
SELECT pg_reload_conf();
```

### Redis 调优

```bash
# 优化 Redis 配置
redis-cli CONFIG SET maxmemory 2gb
redis-cli CONFIG SET maxmemory-policy allkeys-lru
redis-cli CONFIG SET save ""
```

### Docker 调优

```bash
# 增加文件描述符限制
ulimit -n 65535

# 优化 Docker 存储驱动
cat /etc/docker/daemon.json
{
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
```

---

## 📞 支持

- **问题反馈**: https://github.com/spharx/agentrt/issues
- **文档**: https://github.com/spharx/agentrt#readme
- **Discord**: https://discord.gg/spharx
- **邮件**: support@spharx.cn

---

© 2025-2026 SPHARX Ltd. All Rights Reserved.
