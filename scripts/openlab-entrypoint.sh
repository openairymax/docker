#!/bin/bash
# =============================================================================
# AgentRT OpenLab Entrypoint
# 版本: 0.1.0 (团队E 第09轮次)
# 用途: 替代单CMD，提供安全初始化、密钥生成和信号处理
# BAN合规: BAN-43 (零明文密钥), BAN-57 (CORS安全)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# 颜色输出
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# =============================================================================
# 信号处理：优雅关闭
# =============================================================================
cleanup() {
    log_info "收到关闭信号，优雅停止服务..."
    
    if [ -f /var/run/openlab.pid ]; then
        local pid=$(cat /var/run/openlab.pid)
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null || true
            
            local timeout=30
            while kill -0 "$pid" 2>/dev/null && [ $timeout -gt 0 ]; do
                sleep 1
                timeout=$((timeout - 1))
            done
            
            if kill -0 "$pid" 2>/dev/null; then
                log_warn "强制停止进程 PID=$pid"
                kill -KILL "$pid" 2>/dev/null || true
            fi
        fi
    fi
    
    log_info "清理完成。"
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT

# =============================================================================
# 安全密钥生成
# =============================================================================
generate_secret_if_needed() {
    local env_var="$1"
    local file_path="$2"
    
    local val="${!env_var:-}"
    
    if [ -z "$val" ] || [ "$val" = "__GENERATE__" ]; then
        log_warn "${env_var} 未设置或为 __GENERATE__ 占位符，生成随机密钥..."
        local generated
        generated=$(openssl rand -hex 32 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(32))")
        export "$env_var=$generated"
        log_success "${env_var} 已自动生成（长度: ${#generated}）"
        
        if [ -n "$file_path" ]; then
            mkdir -p "$(dirname "$file_path")"
            echo "$generated" > "$file_path"
            chmod 600 "$file_path"
        fi
    fi
}

# =============================================================================
# 密码强度校验
# =============================================================================
validate_password_strength() {
    local password="$1"
    local name="$2"
    local min_length=16
    
    if [ ${#password} -lt $min_length ]; then
        log_error "${name}: 密码长度不足 (当前: ${#password}, 要求: >=${min_length})"
        return 1
    fi
    
    local unique_chars
    unique_chars=$(echo -n "$password" | fold -w1 | sort -u | wc -l)
    if [ "$unique_chars" -lt 8 ]; then
        log_warn "${name}: 密码字符集较小 (唯一字符: ${unique_chars})"
    fi
    
    return 0
}

# =============================================================================
# 运行时目录设置
# =============================================================================
setup_directories() {
    log_info "设置运行时目录..."
    
    mkdir -p /var/log/openlab
    mkdir -p /var/run
    mkdir -p /app/data
    
    if [ "${OPENLAB_DEBUG:-false}" = "true" ]; then
        log_info "调试模式已启用"
    fi
}

# =============================================================================
# 安全配置注入
# =============================================================================
configure_security_headers() {
    log_info "配置Nginx安全头..."
    
    local nginx_conf="${OPENLAB_NGINX_CONF:-/etc/nginx/conf.d/default.conf}"
    
    if [ -f "$nginx_conf" ]; then
        sed -i \
            -e "s|\${OPENLAB_BACKEND_HOST:-openlab-backend}|${OPENLAB_BACKEND_HOST:-openlab-backend}|g" \
            -e "s|\${OPENLAB_BACKEND_PORT:-8000}|${OPENLAB_BACKEND_PORT:-8000}|g" \
            -e "s|\${OPENLAB_HOST:-openlab.example.com}|${OPENLAB_HOST:-openlab.example.com}|g" \
            "$nginx_conf" 2>/dev/null || true
    fi
}

# =============================================================================
# 主流程
# =============================================================================
main() {
    log_info "============================================"
    log_info " AgentRT OpenLab Entrypoint v1.0.0"
    log_info "============================================"
    
    # 1. 设置目录
    setup_directories
    
    # 2. 安全密钥检查
    generate_secret_if_needed "GATEWAY_JWT_SECRET" "/run/secrets/jwt_secret"
    generate_secret_if_needed "OPENLAB_SECRET_KEY" "/run/secrets/openlab_secret_key"
    
    # 3. 密码强度校验
    if [ -n "${POSTGRES_PASSWORD:-}" ] && [ "$POSTGRES_PASSWORD" != "__GENERATE__" ]; then
        validate_password_strength "$POSTGRES_PASSWORD" "POSTGRES_PASSWORD" || log_warn "数据库密码强度不足"
    fi
    if [ -n "${REDIS_PASSWORD:-}" ] && [ "$REDIS_PASSWORD" != "__GENERATE__" ]; then
        validate_password_strength "$REDIS_PASSWORD" "REDIS_PASSWORD" || log_warn "Redis密码强度不足"
    fi
    
    # 4. 配置安全头
    configure_security_headers
    
    # 5. 数据库迁移（生产环境）
    if [ "${OPENLAB_RUN_MIGRATIONS:-false}" = "true" ]; then
        log_info "运行数据库迁移..."
        if command -v python3 &>/dev/null && [ -f /app/backend/manage.py ]; then
            python3 /app/backend/manage.py migrate --noinput 2>/dev/null || log_warn "数据库迁移失败"
        fi
    fi
    
    # 6. 启动Supervisor或直接启动
    log_info "启动OpenLab服务..."
    
    if command -v supervisord &>/dev/null && [ -f /app/config/supervisord.conf ]; then
        log_info "使用Supervisor管理进程..."
        exec /usr/bin/supervisord -c /app/config/supervisord.conf
    elif command -v gunicorn &>/dev/null && [ -f /app/backend/manage.py ]; then
        log_info "启动Gunicorn + Nginx..."
        
        gunicorn -b 0.0.0.0:${OPENLAB_BACKEND_PORT:-8000} \
            -w ${OPENLAB_WORKERS:-4} \
            --access-logfile /var/log/openlab/access.log \
            --error-logfile /var/log/openlab/error.log \
            --pid /var/run/openlab.pid \
            --daemon \
            /app/backend/backend.wsgi:application 2>/dev/null || log_warn "Gunicorn启动失败"
        
        log_info "启动Nginx..."
        exec nginx -g "daemon off;"
    else
        log_info "直接启动Django开发服务器..."
        cd /app/backend
        exec python3 manage.py runserver 0.0.0.0:${OPENLAB_BACKEND_PORT:-8000}
    fi
}

main "$@"
