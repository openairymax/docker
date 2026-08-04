# =============================================================================
# AgentRT Secrets Template
# 版本: 0.1.1
# 用途: 定义 Docker Swarm Secrets 的结构和命名约定
#
# 使用说明:
#   1. 复制此文件到项目根目录
#   2. 运行: docker secret create <name> <file>
#   3. 绝对不要提交实际的 secret 文件！
# =============================================================================

# JWT 签名密钥 (256-bit base64url)
# 生成: openssl rand -base64 48 | tr -d '\n=' > jwt-secret.key
# Secret 名称: agentrt_jwt_secret
# 挂载路径: /run/secrets/jwt_secret

# PostgreSQL 数据库密码
# 生成: openssl rand -base64 32 | tr -d '\n' > postgres-password.key
# Secret 名称: agentrt_postgres_password
# 挂载路径: /run/secrets/postgres_password

# Redis 缓存密码
# 生成: openssl rand -hex 32 > redis-password.key
# Secret 名称: agentrt_redis_password
# 挂载路径: /run/secrets/redis_password

# Grafana 管理员密码
# 生成: openssl rand -base64 24 | tr -d '\n' > grafana-password.key
# Secret 名称: agentrt_grafana_password
# 挂载路径: /run/secrets/grafana_password

# OpenLab 应用密钥 (Django SECRET_KEY)
# 生成: python3 -c "import secrets; print(secrets.token_urlsafe(50))" > openlab-secret.key
# Secret 名称: agentrt_openlab_secret_key
# 挂载路径: /run/secrets/openlab_secret_key
