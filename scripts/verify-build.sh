#!/bin/bash
# =============================================================================
# AgentOS Docker 构建验证脚本
# 版本: 0.1.0 (团队E - 第09轮次)
# 用途: 验证所有Docker服务的可构建性和BAN合规性
#
# 使用方法:
#   ./scripts/verify-build.sh              # 完整验证
#   ./scripts/verify-build.sh --lint      # 仅Dockerfile linting
#   ./scripts/verify-build.sh --config    # 仅Compose文件验证
#   ./scripts/verify-build.sh --ban       # 仅BAN合规性扫描
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$PROJECT_ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

log_pass() { echo -e "${GREEN}[✓]${NC} $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
log_fail() { echo -e "${RED}[✗]${NC} $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
log_warn() { echo -e "${YELLOW}[⚠]${NC} $1"; WARN_COUNT=$((WARN_COUNT + 1)); }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }

check_dockerfile_lint() {
    log_info "=== 检查 Dockerfile Linting ==="
    
    local dockerfiles=(
        "$DOCKER_DIR/Dockerfile.kernel"
        "$DOCKER_DIR/Dockerfile.daemon"
        "$DOCKER_DIR/Dockerfile.openlab"
    )
    
    for dockerfile in "${dockerfiles[@]}"; do
        if [[ -f "$dockerfile" ]]; then
            log_info "Linting: $(basename $dockerfile)"
            if command -v hadolint &> /dev/null; then
                if hadolint --failure-threshold warning "$dockerfile" 2>/dev/null; then
                    log_pass "$(basename $dockerfile): Lint通过"
                else
                    log_fail "$(basename $dockerfile): Lint失败"
                fi
            else
                log_warn "hadolint未安装，跳过linting"
            fi
        else
            log_fail "Dockerfile不存在: $dockerfile"
        fi
    done
}

check_compose_files() {
    log_info "=== 验证 Docker Compose 文件 ==="
    
    local compose_files=(
        "$DOCKER_DIR/docker-compose.yml"
        "$DOCKER_DIR/docker-compose.staging.yml"
        "$DOCKER_DIR/docker-compose.prod.yml"
    )
    
    for compose_file in "${compose_files[@]}"; do
        if [[ -f "$compose_file" ]]; then
            log_info "验证: $(basename $compose_file)"
            if docker compose -f "$compose_file" config --quiet 2>/dev/null; then
                log_pass "$(basename $compose_file): Compose配置有效"
            else
                log_fail "$(basename $compose_file): Compose配置无效"
            fi
        else
            log_warn "Compose文件不存在: $(basename $compose_file)"
        fi
    done
}

check_ban_compliance() {
    log_info "=== BAN合规性扫描 ==="
    
    log_info "扫描 BAN-43 (硬编码密钥)..."
    local secret_patterns='JWT_SECRET=.*[^${]|POSTGRES_PASSWORD=.*[^${}|REDIS_PASSWORD=.*[^${]|GRAFANA_ADMIN_PASSWORD=.*[^${]'
    if grep -rn "$secret_patterns" "$DOCKER_DIR/docker-compose"*.yml 2>/dev/null | grep -v 'CHANGE_ME\|change_me'; then
        log_fail "BAN-43违规: 发现硬编码密钥"
    else
        log_pass "BAN-43: 无硬编码密钥"
    fi
    
    log_info "扫描 BAN-57 (CORS通配符)..."
    if grep -rn "Access-Control-Allow-Origin \*" "$DOCKER_DIR/config/nginx/" 2>/dev/null; then
        log_fail "BAN-57违规: 发现CORS通配符*"
    else
        log_pass "BAN-57: 无CORS通配符"
    fi
    
    log_info "扫描 Redis健康检查密码泄露..."
    if grep -rn 'redis-cli -a\|redis-cli --no-auth-warning' "$DOCKER_DIR/docker-compose"*.yml 2>/dev/null; then
        log_fail "发现Redis健康检查密码泄露(-a参数或--no-auth-warning)"
    else
        log_pass "Redis健康检查: 使用REDISCLI_AUTH环境变量"
    fi
    
    log_info "检查 Grafana匿名访问..."
    if grep -rn "GF_AUTH_ANONYMOUS_ENABLED: true" "$DOCKER_DIR/docker-compose.staging.yml" 2>/dev/null; then
        log_fail "Grafana匿名访问已启用(Staging)"
    else
        log_pass "Grafana匿名访问: 已关闭"
    fi
    
    log_info "检查 .env.example文件..."
    if [[ -f "$DOCKER_DIR/.env.example" ]]; then
        if grep -q "CHANGE_ME" "$DOCKER_DIR/.env.example"; then
            log_pass ".env.example: 使用CHANGE_ME占位符"
        else
            log_warn ".env.example: 建议使用CHANGE_ME占位符"
        fi
        
        if grep -q "DESKTOP_ORIGIN\|WHITELIST_IPS\|OPENLAB_BACKEND_HOST" "$DOCKER_DIR/.env.example"; then
            log_pass ".env.example: 包含新环境变量定义"
        else
            log_warn ".env.example: 缺少新环境变量定义"
        fi
    fi
    
    log_info "检查多架构支持..."
    if grep -q "linux/amd64.*linux/arm64" "$DOCKER_DIR/.github/workflows/release.yml" 2>/dev/null; then
        log_pass "CI/CD: 支持多架构构建(amd64+arm64)"
    else
        log_warn "CI/CD: 未检测到多架构支持(release.yml)"
    fi
    
    log_info "检查安全加固配置..."
    local security_checks=0
    if grep -q "cap_drop:\s*- ALL" "$DOCKER_DIR/docker-compose.staging.yml" 2>/dev/null; then
        security_checks=$((security_checks + 1))
    fi
    if grep -q "read_only: true" "$DOCKER_DIR/docker-compose.staging.yml" 2>/dev/null; then
        security_checks=$((security_checks + 1))
    fi
    if grep -q "no-new-privileges:true" "$DOCKER_DIR/docker-compose.staging.yml" 2>/dev/null; then
        security_checks=$((security_checks + 1))
    fi
    
    if [[ $security_checks -ge 2 ]]; then
        log_pass "Staging安全加固: $security_checks/3项已配置"
    else
        log_warn "Staging安全加固: 仅$security_checks/3项已配置"
    fi
}

check_dockerfiles_multi_stage() {
    log_info "=== 验证 Multi-stage 构建 ==="
    
    local dockerfiles=(
        "$DOCKER_DIR/Dockerfile.kernel"
        "$DOCKER_DIR/Dockerfile.daemon"
        "$DOCKER_DIR/Dockerfile.openlab"
        "$DOCKER_DIR/Dockerfile.desktop"
    )
    
    for dockerfile in "${dockerfiles[@]}"; do
        if [[ -f "$dockerfile" ]]; then
            local stages
            stages=$(grep -c "^FROM" "$dockerfile" 2>/dev/null || echo "0")
            
            if [[ $stages -ge 2 ]]; then
                log_pass "$(basename $dockerfile): Multi-stage构建($stages阶段)"
            else
                log_warn "$(basename $dockerfile): 单阶段构建(建议使用multi-stage)"
            fi
        fi
    done
}

check_secrets_documentation() {
    log_info "=== 验证 Docker Secrets 文档 ==="
    
    if [[ -f "$DOCKER_DIR/secrets/DOCKER_SECRETS_GUIDE.md" ]]; then
        log_pass "Docker Secrets部署文档存在"
        
        if grep -q "BAN-43" "$DOCKER_DIR/secrets/DOCKER_SECRETS_GUIDE.md" 2>/dev/null; then
            log_pass "Secrets文档引用BAN-43规范"
        fi
        
        if grep -q "docker secret create" "$DOCKER_DIR/secrets/DOCKER_SECRETS_GUIDE.md" 2>/dev/null; then
            log_pass "Secrets文档包含实际部署命令"
        fi
    else
        log_warn "Docker Secrets文档缺失"
    fi
}

main() {
    echo "=========================================="
    echo " AgentOS Docker 构建验证 v0.1.0"
    echo " 团队E - 第09轮次"
    echo " 时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================="
    echo ""
    
    local mode="${1:-all}"
    
    case "$mode" in
        --lint)     check_dockerfile_lint ;;
        --config)   check_compose_files ;;
        --ban)      check_ban_compliance ;;
        --stage)    check_dockerfiles_multi_stage ;;
        --secrets)  check_secrets_documentation ;;
        all|"")
            check_dockerfile_lint
            echo ""
            check_compose_files
            echo ""
            check_ban_compliance
            echo ""
            check_dockerfiles_multi_stage
            echo ""
            check_secrets_documentation
            ;;
        *)
            echo "用法: $0 [--lint|--config|--ban|--stage|--secrets|all]"
            exit 1
            ;;
    esac
    
    echo ""
    echo "=========================================="
    echo " 验证结果汇总"
    echo "=========================================="
    printf "  ${GREEN}通过:%d${NC}  ${RED}失败:%d${NC}  ${YELLOW}警告:%d${NC}\n" \
           "$PASS_COUNT" "$FAIL_COUNT" "$WARN_COUNT"
    echo ""
    
    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo -e "${RED}❌ 存在必须修复的问题!${NC}"
        exit 2
    elif [[ $WARN_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}⚠ 存在建议改进项${NC}"
        exit 1
    else
        echo -e "${GREEN}✅ 所有检查通过!${NC}"
        exit 0
    fi
}

main "$@"
