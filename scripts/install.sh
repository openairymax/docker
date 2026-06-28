#!/bin/bash
# =============================================================================
# AgentOS Docker 一键安装脚本
# 版本: 0.1.0
# 支持: Linux (Ubuntu/Debian/CentOS), macOS
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# 常量定义
# -----------------------------------------------------------------------------
readonly AGENTOS_VERSION="${AGENTOS_VERSION:-0.1.0}"
readonly INSTALL_DIR="${HOME}/.agentos"
readonly DOCKER_CONFIG_DIR="${HOME}/.docker"
readonly REPO_URL="https://github.com/spharx/agentos"
readonly INSTALL_SCRIPT_URL="${REPO_URL}/raw/main/docker/scripts/install.sh"

# 颜色输出
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
    echo -e "${NC}Docker Edition v${AGENTOS_VERSION}"
    echo ""
}

# -----------------------------------------------------------------------------
# 检查前置条件
# -----------------------------------------------------------------------------
check_prerequisites() {
    echo -e "${BLUE}[1/5] 检查环境...${NC}"

    # 检查 root 权限 (Docker 需要)
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}⚠️ 建议使用 sudo 运行以获得完整功能${NC}"
    fi

    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}✗ Docker 未安装${NC}"
        echo "请先安装 Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi

    local docker_version
    docker_version=$(docker --version 2>/dev/null | awk '{print $3}' | cut -d',' -f1)
    echo -e "${GREEN}✓ Docker ${docker_version}${NC}"

    # 检查 Docker Compose
    if ! docker compose version &> /dev/null 2>&1; then
        echo -e "${RED}✗ Docker Compose V2 未安装${NC}"
        echo "请先安装 Docker Compose V2"
        exit 1
    fi
    echo -e "${GREEN}✓ Docker Compose$(docker compose version 2>/dev/null | head -1)${NC}"

    # 检查系统资源
    local mem_kb
    mem_kb=$(free -k 2>/dev/null | awk '/Mem:/{print $2}' || sysctl -n hw.memsize 2>/dev/null | awk '{print $1/1024}')
    local mem_gb=$((mem_kb / 1024 / 1024))
    if [[ -n "$mem_gb" ]] && [[ "$mem_gb" -lt 4 ]]; then
        echo -e "${YELLOW}⚠️ 内存不足: ${mem_gb}GB (建议 ≥4GB)${NC}"
    else
        echo -e "${GREEN}✓ 内存充足${NC}"
    fi

    echo ""
}

# -----------------------------------------------------------------------------
# 下载 Docker 模块
# -----------------------------------------------------------------------------
download_module() {
    echo -e "${BLUE}[2/5] 下载 AgentOS Docker 模块...${NC}"

    local target_dir="${INSTALL_DIR}/docker-${AGENTOS_VERSION}"
    local docker_dir="${INSTALL_DIR}/docker"

    # 如果已存在，跳过下载
    if [[ -d "${docker_dir}" ]]; then
        echo -e "${YELLOW}⚠️ 检测到已有安装，是否更新? (y/N)${NC}"
        read -r confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "使用现有安装..."
            return 0
        fi
        rm -rf "${docker_dir}"
    fi

    # 创建目录
    mkdir -p "${INSTALL_DIR}"

    # 克隆或下载
    if command -v git &> /dev/null; then
        echo "从 GitHub 克隆..."
        git clone --depth 1 --branch "v${AGENTOS_VERSION}" \
            "https://github.com/spharx/agentos.git" \
            "${INSTALL_DIR}/temp-clone" 2>/dev/null || \
        git clone --depth 1 "https://github.com/spharx/agentos.git" "${INSTALL_DIR}/temp-clone"
        mv "${INSTALL_DIR}/temp-clone/docker" "${docker_dir}"
        rm -rf "${INSTALL_DIR}/temp-clone"
    else
        echo "下载 archive..."
        curl -fsSL "${REPO_URL}/archive/refs/tags/v${AGENTOS_VERSION}.tar.gz" | \
            tar -xz -C "${INSTALL_DIR}"
        mv "${INSTALL_DIR}/agentos-${AGENTOS_VERSION#v}/docker" "${docker_dir}"
        rm -rf "${INSTALL_DIR}/agentos-${AGENTOS_VERSION#v}"
    fi

    echo -e "${GREEN}✓ 下载完成: ${docker_dir}${NC}"
    echo ""
}

# -----------------------------------------------------------------------------
# 预配置
# -----------------------------------------------------------------------------
configure_installation() {
    echo -e "${BLUE}[3/5] 配置环境...${NC}"

    local docker_dir="${INSTALL_DIR}/docker"

    # 创建 .env 文件
    if [[ ! -f "${docker_dir}/.env" ]]; then
        if [[ -f "${docker_dir}/.env.example" ]]; then
            cp "${docker_dir}/.env.example" "${docker_dir}/.env"
            echo -e "${GREEN}✓ 已创建 .env 配置文件${NC}"
            echo -e "${YELLOW}⚠️ 请编辑 ${docker_dir}/.env 修改默认密码${NC}"
        fi
    fi

    # 确保脚本可执行
    chmod +x "${docker_dir}/scripts/"*.sh 2>/dev/null || true

    echo ""
}

# -----------------------------------------------------------------------------
# 拉取/构建镜像
# -----------------------------------------------------------------------------
prepare_images() {
    echo -e "${BLUE}[4/5] 准备 Docker 镜像...${NC}"

    local docker_dir="${INSTALL_DIR}/docker"

    echo "选择镜像源:"
    echo "  1) 从 Docker Hub 拉取预构建镜像 (推荐)"
    echo "  2) 本地构建镜像 (需要源码)"
    echo ""
    read -rp "请选择 [1]: " choice

    case "${choice:-1}" in
        1)
            echo "从 Docker Hub 拉取镜像..."
            docker pull "spharx/agentos-kernel:${AGENTOS_VERSION}" || \
            echo -e "${YELLOW}⚠️ 镜像不存在，请选择选项 2 本地构建${NC}"
            ;;
        2)
            echo "构建本地镜像..."
            docker compose -f "${docker_dir}/docker-compose.yml" build
            ;;
        *)
            echo "无效选择，使用默认选项 1"
            ;;
    esac

    echo ""
}

# -----------------------------------------------------------------------------
# 完成安装
# -----------------------------------------------------------------------------
complete_installation() {
    echo -e "${BLUE}[5/5] 完成安装...${NC}"

    local docker_dir="${INSTALL_DIR}/docker"

    # 创建快捷命令
    local bin_dir="${HOME}/.local/bin"
    mkdir -p "${bin_dir}"

    # 创建 agentos 命令
    cat > "${bin_dir}/agentos" <<'AGENTOS_EOF'
#!/bin/bash
AGENTOS_DIR="${HOME}/.agentos/docker"
cd "${AGENTOS_DIR}" 2>/dev/null || { echo "Error: AgentOS not installed"; exit 1; }
docker compose -f docker-compose.yml "$@"
AGENTOS_EOF
    chmod +x "${bin_dir}/agentos"

    # 添加到 PATH (如果需要)
    if [[ ":$PATH:" != *":${bin_dir}:"* ]]; then
        echo "" >> "${HOME}/.bashrc" 2>/dev/null || true
        echo "export PATH=\"\${HOME}/.local/bin:\$PATH\"" >> "${HOME}/.bashrc" 2>/dev/null || true
        echo -e "${YELLOW}⚠️ 已添加 ${bin_dir} 到 PATH，请重启终端或运行: source ~/.bashrc${NC}"
    fi

    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}  ✅ AgentOS Docker 安装成功!${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    echo -e "${CYAN}快速开始:${NC}"
    echo "  cd ${docker_dir}"
    echo "  docker compose up -d"
    echo ""
    echo -e "${CYAN}或者使用快捷命令:${NC}"
    echo "  agentos up -d"
    echo ""
    echo -e "${CYAN}访问地址:${NC}"
    echo "  • Gateway API: http://localhost:18789"
    echo "  • Kernel IPC:  http://localhost:18080"
    echo "  • PostgreSQL:  localhost:5432"
    echo "  • Redis:       localhost:6379"
    echo ""
    echo -e "${CYAN}常用命令:${NC}"
    echo "  agentos logs -f          # 查看日志"
    echo "  agentos ps               # 服务状态"
    echo "  agentos down             # 停止服务"
    echo ""
}

# -----------------------------------------------------------------------------
# 卸载
# -----------------------------------------------------------------------------
uninstall() {
    echo -e "${RED}[卸载] AgentOS Docker${NC}"
    read -p "确定要卸载吗? (y/N): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        # 停止所有容器
        cd "${INSTALL_DIR}/docker" 2>/dev/null && docker compose down -v 2>/dev/null || true

        # 删除文件
        rm -rf "${INSTALL_DIR}"
        rm -f "${HOME}/.local/bin/agentos"

        echo -e "${GREEN}✓ 卸载完成${NC}"
    fi
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    show_logo

    local command="${1:-install}"

    case "$command" in
        install)
            check_prerequisites
            download_module
            configure_installation
            prepare_images
            complete_installation
            ;;
        uninstall|remove)
            uninstall
            ;;
        update|upgrade)
            AGENTOS_VERSION="${2:-${AGENTOS_VERSION}}" && export AGENTOS_VERSION
            check_prerequisites
            download_module
            configure_installation
            echo -e "${GREEN}✓ 更新完成${NC}"
            ;;
        *)
            echo "用法: $0 [install|uninstall|update]"
            echo ""
            echo "  install   安装 AgentOS (默认)"
            echo "  update    更新到新版本"
            echo "  uninstall 卸载 AgentOS"
            exit 1
            ;;
    esac
}

main "$@"
