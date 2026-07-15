#!/bin/bash
# =============================================================================
# AgentRT Docker 快速启动脚本 (Quick Start Script)
# 版本: 0.1.0
# 最后更新: 2026-05-04
#
# 使用方法:
#   ./scripts/quick-start.sh              # 交互式启动
#   ./scripts/quick-start.sh dev          # 启动开发环境
#   ./scripts/quick-start.sh staging      # 启动预发布环境
#   ./scripts/quick-start.sh --check      # 仅检查环境
#   ./scripts/quick-start.sh --clean      # 清理所有资源
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# 全局变量
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$SCRIPT_DIR/.."
PROJECT_ROOT="$(cd "$DOCKER_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logo
show_logo() {
    echo -e "${CYAN}"
    cat <<'EOF'
    ____        _   _____           _
   / __ \__  __(_) / ___/__  ______(_)___  ___
  / /_/ / / / / / /\__ \/ / / /_  __/ / __ \/ _ \
 / _, _/ /_/ / / /___/ / /_/ / / / / / / /  __/
/_/ |_|\__,_/_/  /____/\__,_/ /_/ /_/_/  \___/

EOF
    echo -e "${NC}"
}

# -----------------------------------------------------------------------------
# 环境检查
# -----------------------------------------------------------------------------
check_prerequisites() {
    echo -e "${BLUE}[检查] 环境依赖...${NC}"

    local missing=0

    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}✗ Docker 未安装${NC}"
        ((missing++))
    else
        local docker_version
        docker_version=$(docker --version | awk '{print $3}' | cut -d',' -f1)
        echo -e "${GREEN}✓ Docker ${docker_version}${NC}"
    fi

    # 检查 Docker Compose
    if ! docker compose version &> /dev/null 2>&1; then
        echo -e "${RED}✗ Docker Compose 未安装${NC}"
        ((missing++))
    else
        local compose_version
        compose_version=$(docker compose version | head -1)
        echo -e "${GREEN}✓ ${compose_version}${NC}"
    fi

    # 检查可用内存
    if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "darwin"* ]]; then
        local total_mem
        total_mem=$(free -g 2>/dev/null | awk '/Mem:/{print $2}' || sysctl hw.memsize | awk '{print $2/1024/1024/1024}')
        if [[ -n "$total_mem" ]] && [[ "$total_mem" -lt 8 ]]; then
            echo -e "${YELLOW}⚠ 内存不足: ${total_mem}GB (建议 ≥8GB)${NC}"
        else
            echo -e "${GREEN}✓ 内存: ${total_mem}GB${NC}"
        fi
    fi

    # 检查磁盘空间
    local disk_free
    disk_free=$(df -h . | tail -1 | awk '{print $4}')
    echo -e "${GREEN}✓ 可用磁盘: ${disk_free}${NC}"

    if [[ $missing -gt 0 ]]; then
        echo ""
        echo -e "${RED}[错误] 缺少 $missing 个必要依赖，请先安装后再试${NC}"
        exit 1
    fi

    echo ""
}

# -----------------------------------------------------------------------------
# 启动函数
# -----------------------------------------------------------------------------
start_dev() {
    echo -e "${YELLOW}[启动] 开发环境...${NC}"
    
    cd "$PROJECT_ROOT"
    
    # 创建 .env 文件（如果不存在）
    if [[ ! -f "$DOCKER_DIR/.env" ]]; then
        cp "$DOCKER_DIR/.env.example" "$DOCKER_DIR/.env" 2>/dev/null || true
        echo -e "${CYAN}已创建 .env 配置文件${NC}"
    fi

    # 自动生成随机密码 (BAN-43合规)
    generate_passwords_if_needed "$DOCKER_DIR/.env"
    
    docker compose -f "$DOCKER_DIR/docker-compose.yml" up -d
    
    show_access_info dev
}

start_staging() {
    echo -e "${YELLOW}[启动] 预发布环境...${NC}"
    
    cd "$PROJECT_ROOT"
    
    # 创建 .env.staging 文件（如果不存在）
    if [[ ! -f "$DOCKER_DIR/.env.staging" ]]; then
        cp "$DOCKER_DIR/.env.staging.example" "$DOCKER_DIR/.env.staging"
        echo -e "${CYAN}已创建 .env.staging 配置文件${NC}"
    fi

    # 自动生成随机密码 (BAN-43合规)
    generate_passwords_if_needed "$DOCKER_DIR/.env.staging"
    
    docker compose -f "$DOCKER_DIR/docker-compose.staging.yml" \
        --env-file "$DOCKER_DIR/.env.staging" up -d
    
    show_access_info staging
}

start_prod() {
    if [[ ! -f "$DOCKER_DIR/.env.production" ]]; then
        cp "$DOCKER_DIR/.env.production.example" "$DOCKER_DIR/.env.production" 2>/dev/null || true
        echo -e "${CYAN}已创建 .env.production 配置文件${NC}"
    fi

    # 自动生成随机密码 (BAN-43合规)
    generate_passwords_if_needed "$DOCKER_DIR/.env.production"
    
    if grep -q "__GENERATE__\|__GENERATE_USERNAME__" "$DOCKER_DIR/.env.production" 2>/dev/null; then
        echo -e "${RED}[错误] 生产环境存在未生成的 __GENERATE__ 占位符，请检查以上输出${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}[启动] 生产环境...${NC}"
    
    cd "$PROJECT_ROOT"
    docker compose -f "$DOCKER_DIR/docker-compose.prod.yml" \
        --env-file "$DOCKER_DIR/.env.production" up -d
    
    show_access_info prod
}

# -----------------------------------------------------------------------------
# 显示访问信息
# -----------------------------------------------------------------------------
show_access_info() {
    local env="$1"
    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}  AgentRT ${env^^} 环境启动成功!${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""

    case "$env" in
        dev)
            echo -e "  ${CYAN}服务地址:${NC}"
            echo -e "  • Gateway API:     http://localhost:18789"
            echo -e "  • Gateway Admin:   http://localhost:18790"
            echo -e "  • Kernel IPC:     http://localhost:18080"
            echo -e "  • Kernel Metrics: http://localhost:9090"
            echo -e "  • PostgreSQL:     localhost:5432"
            echo -e "  • Redis:          localhost:6379"
            echo ""
            echo -e "  ${CYAN}常用命令:${NC}"
            echo -e "  make logs         # 查看日志"
            echo -e "  make status       # 服务状态"
            echo -e "  make healthcheck  # 健康检查"
            ;;
        staging)
            echo -e "  ${CYAN}服务地址:${NC}"
            echo -e "  • Gateway API:     http://localhost:18789"
            echo -e "  • Kernel IPC:     http://localhost:18080"
            echo -e "  • PostgreSQL:     localhost:15432"
            echo -e "  • Redis:          localhost:16379"
            echo -e "  • Prometheus:     http://localhost:9091"
            echo -e "  • Grafana:        http://localhost:3000"
            ;;
        prod)
            echo -e "  ${CYAN}服务地址:${NC}"
            echo -e "  • Gateway API:     https://your-domain.com"
            echo -e "  • Grafana:        https://your-domain.com/grafana (VPN Only)"
            echo ""
            echo -e "  ${YELLOW}⚠️ 请通过反向代理访问生产环境${NC}"
            ;;
    esac

    echo ""
    echo -e "${CYAN}运行健康检查: ./scripts/healthcheck.sh${NC}"
    echo ""
}

# -----------------------------------------------------------------------------
# 停止和清理
# -----------------------------------------------------------------------------
stop_all() {
    echo -e "${YELLOW}[停止] 所有服务...${NC}"
    cd "$PROJECT_ROOT"
    docker compose -f "$DOCKER_DIR/docker-compose.yml" down --timeout 60
    docker compose -f "$DOCKER_DIR/docker-compose.staging.yml" down --timeout 60 2>/dev/null || true
    echo -e "${GREEN}[完成] 服务已停止${NC}"
}

cleanup_all() {
    echo -e "${RED}[清理] 这将删除所有数据卷! 继续? (y/N)${NC}"
    read -r confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        cd "$PROJECT_ROOT"
        docker compose -f "$DOCKER_DIR/docker-compose.yml" down -v
        docker system prune -a -f
        docker volume prune -a -f
        echo -e "${GREEN}[完成] 完全清理完成${NC}"
    else
        echo "取消操作"
    fi
}

# -----------------------------------------------------------------------------
# 主菜单
# -----------------------------------------------------------------------------
show_menu() {
    echo -e "${BLUE}请选择操作:${NC}"
    echo "  1) 启动开发环境 (Development)"
    echo "  2) 启动预发布环境 (Staging)"
    echo "  3) 启动生产环境 (Production)"
    echo "  4) 停止所有服务 (Stop)"
    echo "  5) 完全清理 (Cleanup)"
    echo "  6) 运行健康检查 (Health Check)"
    echo "  0) 退出 (Exit)"
    echo ""
    read -rp "$(echo -e ${CYAN})请输入选项 [0-6]: $(echo -e ${NC})" choice
}

# -----------------------------------------------------------------------------
# 主执行流程
# -----------------------------------------------------------------------------
main() {
    show_logo

    # 如果有命令行参数，直接执行
    case "${1:-}" in
        dev)
            check_prerequisites
            start_dev
            exit 0
            ;;
        staging)
            check_prerequisites
            start_staging
            exit 0
            ;;
        prod)
            check_prerequisites
            start_prod
            exit 0
            ;;
        stop)
            stop_all
            exit 0
            ;;
        clean)
            cleanup_all
            exit 0
            ;;
        --check)
            check_prerequisites
            exit 0
            ;;
        --help|-h)
            echo "Usage: $0 [dev|staging|prod|stop|clean|--check|--help]"
            exit 0
            ;;
    esac

    # 交互模式
    check_prerequisites

    while true; do
        show_menu

        case "$choice" in
            1) start_dev ;;
            2) start_staging ;;
            3) start_prod ;;
            4) stop_all ;;
            5) cleanup_all ;;
            6)
                chmod +x "$DOCKER_DIR/scripts/healthcheck.sh"
                "$DOCKER_DIR/scripts/healthcheck.sh"
                ;;
            0)
                echo -e "${CYAN}再见!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项: $choice${NC}"
                ;;
        esac

        echo ""
        read -rp "按 Enter 键继续..."
        clear
        show_logo
    done
}

main "$@"
