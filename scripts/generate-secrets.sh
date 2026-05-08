#!/bin/bash
# =============================================================================
# AgentOS Docker Secrets 生成脚本
# 版本: 0.0.5
# 用途: 为生产环境生成安全的密钥和密码文件
#
# 使用方法:
#   ./scripts/generate-secrets.sh              # 交互式生成
#   ./scripts/generate-secrets.sh --auto       # 自动生成（用于CI/CD）
#   ./scripts/generate-secrets.sh --prod       # 仅生产密钥
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="$SCRIPT_DIR/../secrets"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

generate_secret() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d '\n/+='
}

create_secret_dir() {
    mkdir -p "$SECRETS_DIR" 2>/dev/null || true
    chmod 700 "$SECRETS_DIR"
    echo -e "${GREEN}[OK] Secrets 目录: $SECRETS_DIR${NC}"
}

generate_postgres_secrets() {
    echo -e "${YELLOW}生成 PostgreSQL 密钥...${NC}"
    
    if [[ ! -f "$SECRETS_DIR/postgres_password.txt" ]]; then
        generate_secret 32 > "$SECRETS_DIR/postgres_password.txt"
        chmod 600 "$SECRETS_DIR/postgres_password.txt"
        echo -e "${GREEN}  ✓ postgres_password.txt${NC}"
    else
        echo -e "  - postgres_password.txt (已存在)"
    fi
}

generate_redis_secrets() {
    echo -e "${YELLOW}生成 Redis 密钥...${NC}"
    
    if [[ ! -f "$SECRETS_DIR/redis_password.txt" ]]; then
        generate_secret 32 > "$SECRETS_DIR/redis_password.txt"
        chmod 600 "$SECRETS_DIR/redis_password.txt"
        echo -e "${GREEN}  ✓ redis_password.txt${NC}"
    else
        echo -e "  - redis_password.txt (已存在)"
    fi
}

generate_jwt_secrets() {
    echo -e "${YELLOW}生成 JWT 密钥...${NC}"
    
    if [[ ! -f "$SECRETS_DIR/jwt_secret.txt" ]]; then
        generate_secret 64 > "$SECRETS_DIR/jwt_secret.txt"
        chmod 600 "$SECRETS_DIR/jwt_secret.txt"
        echo -e "${GREEN}  ✓ jwt_secret.txt${NC}"
    else
        echo -e "  - jwt_secret.txt (已存在)"
    fi
}

generate_grafana_secrets() {
    echo -e "${YELLOW}生成 Grafana 密钥...${NC}"
    
    if [[ ! -f "$SECRETS_DIR/grafana_password.txt" ]]; then
        generate_secret 24 > "$SECRETS_DIR/grafana_password.txt"
        chmod 600 "$SECRETS_DIR/grafana_password.txt"
        echo -e "${GREEN}  ✓ grafana_password.txt${NC}"
    else
        echo -e "  - grafana_password.txt (已存在)"
    fi
}

generate_llm_keys() {
    echo -e "${YELLOW}LLM API Keys...${NC}"
    
    set +u
    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        echo "$OPENAI_API_KEY" > "$SECRETS_DIR/openai_api_key.txt"
        chmod 600 "$SECRETS_DIR/openai_api_key.txt"
        echo -e "${GREEN}  ✓ openai_api_key.txt (from env)${NC}"
    fi
    
    if [[ -n "${DEEPSEEK_API_KEY:-}" ]]; then
        echo "$DEEPSEEK_API_KEY" > "$SECRETS_DIR/deepseek_api_key.txt"
        chmod 600 "$SECRETS_DIR/deepseek_api_key.txt"
        echo -e "${GREEN}  ✓ deepseek_api_key.txt (from env)${NC}"
    fi
    set -u
    
    if [[ ! -f "$SECRETS_DIR/openai_api_key.txt" ]]; then
        echo "REPLACE_WITH_OPENAI_API_KEY" > "$SECRETS_DIR/openai_api_key.txt"
        chmod 600 "$SECRETS_DIR/openai_api_key.txt"
        echo -e "${YELLOW}  ! openai_api_key.txt (请手动替换)${NC}"
    fi
}

main() {
    echo -e "${GREEN}========================================="
    echo -e "  AgentOS Secrets 生成脚本"
    echo -e "=========================================${NC}"
    echo ""
    
    create_secret_dir
    
    case "${1:-}" in
        --prod)
            generate_postgres_secrets
            generate_redis_secrets
            generate_jwt_secrets
            generate_grafana_secrets
            ;;
        --auto)
            generate_postgres_secrets
            generate_redis_secrets
            generate_jwt_secrets
            generate_grafana_secrets
            generate_llm_keys
            ;;
        *)
            generate_postgres_secrets
            generate_redis_secrets
            generate_jwt_secrets
            generate_grafana_secrets
            generate_llm_keys
            ;;
    esac
    
    find "$SECRETS_DIR" -type f -exec chmod 600 {} \;
    
    echo ""
    echo -e "${GREEN}========================================="
    echo -e "  完成! 密钥文件位于: $SECRETS_DIR/"
    echo -e "=========================================${NC}"
    echo ""
    echo -e "${YELLOW}⚠️ 注意: secrets/ 目录已在 .gitignore 中排除${NC}"
    echo -e "${YELLOW}⚠️ 生产部署前请覆盖 LLM API Keys${NC}"
}

main "$@"
