#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[HARDEN]${NC} $*"; }
warn()  { echo -e "${YELLOW}[HARDEN]${NC} $*"; }
error() { echo -e "${RED}[HARDEN]${NC} $*"; }
section() { echo -e "\n${CYAN}=== $* ===${NC}"; }

check_docker_running() {
    if ! docker info >/dev/null 2>&1; then
        error "Docker daemon is not running"
        exit 1
    fi
}

harden_kernel() {
    info "Hardening kernel container..."
    local kernel_id
    kernel_id=$(docker ps --filter "name=kernel" --format '{{.ID}}' | head -1)
    if [ -z "$kernel_id" ]; then
        warn "Kernel container not running, skipping"
        return 0
    fi

    docker exec "$kernel_id" sh -c '
        sysctl -w net.ipv4.ip_forward=0 2>/dev/null || true
        sysctl -w net.ipv4.conf.all.send_redirects=0 2>/dev/null || true
        sysctl -w net.ipv4.conf.all.accept_redirects=0 2>/dev/null || true
        sysctl -w net.ipv4.conf.all.accept_source_route=0 2>/dev/null || true
        sysctl -w net.ipv4.conf.all.log_martians=1 2>/dev/null || true
        sysctl -w kernel.core_pattern="|/bin/false" 2>/dev/null || true
    ' 2>/dev/null || warn "Some sysctl settings could not be applied (expected in container)"

    info "Kernel container hardened"
}

harden_gateway() {
    info "Hardening gateway container..."
    local gateway_id
    gateway_id=$(docker ps --filter "name=gateway" --format '{{.ID}}' | head -1)
    if [ -z "$gateway_id" ]; then
        warn "Gateway container not running, skipping"
        return 0
    fi

    docker exec "$gateway_id" sh -c '
        chmod 600 /app/config/gateway.yaml 2>/dev/null || true
        chmod 700 /app/data 2>/dev/null || true
        chmod 700 /app/logs 2>/dev/null || true
    ' 2>/dev/null || warn "Some permission changes could not be applied"

    info "Gateway container hardened"
}

harden_redis() {
    info "Hardening Redis container..."
    local redis_id
    redis_id=$(docker ps --filter "name=redis" --format '{{.ID}}' | head -1)
    if [ -z "$redis_id" ]; then
        warn "Redis container not running, skipping"
        return 0
    fi

    docker exec "$redis_id" sh -c '
        redis-cli CONFIG SET rename-command FLUSHDB "" 2>/dev/null || true
        redis-cli CONFIG SET rename-command FLUSHALL "" 2>/dev/null || true
        redis-cli CONFIG SET rename-command DEBUG "" 2>/dev/null || true
        redis-cli CONFIG SET stop-writes-on-bgsave-error yes 2>/dev/null || true
    ' 2>/dev/null || warn "Some Redis hardening commands could not be applied"

    info "Redis container hardened"
}

harden_postgres() {
    info "Hardening PostgreSQL container..."
    local pg_id
    pg_id=$(docker ps --filter "name=postgres" --format '{{.ID}}' | head -1)
    if [ -z "$pg_id" ]; then
        warn "PostgreSQL container not running, skipping"
        return 0
    fi

    docker exec "$pg_id" sh -c '
        psql -U agentos -c "ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;" 2>/dev/null || true
        psql -U agentos -c "REVOKE CREATE ON SCHEMA public FROM PUBLIC;" 2>/dev/null || true
    ' 2>/dev/null || warn "Some PostgreSQL hardening commands could not be applied"

    info "PostgreSQL container hardened"
}

harden_docker_daemon() {
    info "Checking Docker daemon security configuration..."
    local issues=0

    if [ -f /etc/docker/daemon.json ]; then
        if grep -q '"live-restore"' /etc/docker/daemon.json; then
            info "Docker live-restore is configured"
        else
            warn "Docker live-restore is not configured (recommended for production)"
            issues=$((issues + 1))
        fi

        if grep -q '"userns-remap"' /etc/docker/daemon.json; then
            info "Docker user namespace remapping is configured"
        else
            warn "Docker user namespace remapping is not configured (recommended for high-security)"
            issues=$((issues + 1))
        fi

        if grep -q '"log-driver"' /etc/docker/daemon.json; then
            info "Docker log driver is configured"
        else
            warn "Docker log driver is not configured (recommended: json-file or local)"
            issues=$((issues + 1))
        fi

        if grep -q '"storage-driver"' /etc/docker/daemon.json; then
            info "Docker storage driver is configured"
        else
            warn "Docker storage driver is not explicitly configured"
            issues=$((issues + 1))
        fi
    else
        warn "/etc/docker/daemon.json not found"
        issues=$((issues + 1))
    fi

    if [ "$issues" -eq 0 ]; then
        info "Docker daemon security configuration is adequate"
    else
        warn "Docker daemon has $issues security configuration issue(s)"
    fi

    return $issues
}

verify_image_signatures() {
    info "Verifying Docker Content Trust..."
    local images
    images=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>' | head -20)
    local unsigned=0

    if [ -n "${DOCKER_CONTENT_TRUST:-}" ] && [ "$DOCKER_CONTENT_TRUST" = "1" ]; then
        info "DOCKER_CONTENT_TRUST is enabled"
    else
        warn "DOCKER_CONTENT_TRUST is not enabled (set DOCKER_CONTENT_TRUST=1 for production)"
        unsigned=$((unsigned + 1))
    fi

    for img in $images; do
        if echo "$img" | grep -q "spharx/"; then
            info "Found AgentOS image: $img"
        fi
    done

    return $unsigned
}

scan_vulnerabilities() {
    info "Checking for image vulnerability scanner..."
    if command -v trivy >/dev/null 2>&1; then
        info "Trivy found, scanning AgentOS images..."
        local images
        images=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'spharx/' | head -5)
        for img in $images; do
            info "Scanning $img..."
            trivy image --severity HIGH,CRITICAL --no-progress "$img" 2>/dev/null || \
                warn "Vulnerability scan failed for $img"
        done
    else
        warn "Trivy not installed. Install: https://aquasecurity.github.io/trivy/"
        warn "Alternative: docker scout cves <image>"
    fi
}

verify_security() {
    section "Security Verification"
    local issues=0

    local kernel_id
    kernel_id=$(docker ps --filter "name=kernel" --format '{{.ID}}' | head -1)
    if [ -n "$kernel_id" ]; then
        local kernel_user
        kernel_user=$(docker exec "$kernel_id" whoami 2>/dev/null || echo "unknown")
        if [ "$kernel_user" = "root" ]; then
            warn "Kernel container running as root (should use non-root user)"
            issues=$((issues + 1))
        else
            info "Kernel container running as: $kernel_user (OK)"
        fi

        local kernel_ro
        kernel_ro=$(docker inspect --format '{{.HostConfig.ReadonlyRootfs}}' "$kernel_id" 2>/dev/null || echo "false")
        if [ "$kernel_ro" = "true" ]; then
            info "Kernel container has read-only filesystem (OK)"
        else
            warn "Kernel container does not have read-only filesystem"
            issues=$((issues + 1))
        fi

        local kernel_priv
        kernel_priv=$(docker inspect --format '{{.HostConfig.Privileged}}' "$kernel_id" 2>/dev/null || echo "false")
        if [ "$kernel_priv" = "true" ]; then
            error "Kernel container is running in privileged mode (CRITICAL)"
            issues=$((issues + 1))
        else
            info "Kernel container is not privileged (OK)"
        fi

        local kernel_newpriv
        kernel_newpriv=$(docker inspect --format '{{.HostConfig.SecurityOpt}}' "$kernel_id" 2>/dev/null || echo "")
        if echo "$kernel_newpriv" | grep -q "no-new-privileges"; then
            info "Kernel container has no-new-privileges (OK)"
        else
            warn "Kernel container missing no-new-privileges"
            issues=$((issues + 1))
        fi
    fi

    local gateway_id
    gateway_id=$(docker ps --filter "name=gateway" --format '{{.ID}}' | head -1)
    if [ -n "$gateway_id" ]; then
        local gateway_user
        gateway_user=$(docker exec "$gateway_id" whoami 2>/dev/null || echo "unknown")
        if [ "$gateway_user" = "root" ]; then
            warn "Gateway container running as root (should use non-root user)"
            issues=$((issues + 1))
        else
            info "Gateway container running as: $gateway_user (OK)"
        fi

        local gateway_priv
        gateway_priv=$(docker inspect --format '{{.HostConfig.Privileged}}' "$gateway_id" 2>/dev/null || echo "false")
        if [ "$gateway_priv" = "true" ]; then
            error "Gateway container is running in privileged mode (CRITICAL)"
            issues=$((issues + 1))
        else
            info "Gateway container is not privileged (OK)"
        fi
    fi

    local exposed_ports
    exposed_ports=$(docker ps --format '{{.Ports}}' 2>/dev/null | grep -c '0.0.0.0' || echo "0")
    if [ "$exposed_ports" -gt 0 ]; then
        warn "$exposed_ports container(s) have ports exposed to 0.0.0.0"
        issues=$((issues + 1))
    else
        info "No containers expose ports to 0.0.0.0 (OK)"
    fi

    local privileged_count
    privileged_count=$(docker ps -q --filter "status=running" | while read -r cid; do
        docker inspect --format '{{.HostConfig.Privileged}}' "$cid" 2>/dev/null
    done | grep -c "true" || echo "0")
    if [ "$privileged_count" -gt 0 ]; then
        error "$privileged_count container(s) running in privileged mode (CRITICAL)"
        issues=$((issues + 1))
    else
        info "No containers running in privileged mode (OK)"
    fi

    local host_pid_count
    host_pid_count=$(docker ps -q --filter "status=running" | while read -r cid; do
        docker inspect --format '{{.HostConfig.PidMode}}' "$cid" 2>/dev/null
    done | grep -c "host" || echo "0")
    if [ "$host_pid_count" -gt 0 ]; then
        error "$host_pid_count container(s) using host PID namespace (CRITICAL)"
        issues=$((issues + 1))
    else
        info "No containers using host PID namespace (OK)"
    fi

    local host_net_count
    host_net_count=$(docker ps -q --filter "status=running" | while read -r cid; do
        docker inspect --format '{{.HostConfig.NetworkMode}}' "$cid" 2>/dev/null
    done | grep -c "host" || echo "0")
    if [ "$host_net_count" -gt 0 ]; then
        warn "$host_net_count container(s) using host network namespace"
        issues=$((issues + 1))
    else
        info "No containers using host network namespace (OK)"
    fi

    if [ -f .env.production ]; then
        local env_perms
        env_perms=$(stat -c '%a' .env.production 2>/dev/null || stat -f '%Lp' .env.production 2>/dev/null || echo "644")
        if [ "$env_perms" = "600" ] || [ "$env_perms" = "400" ]; then
            info ".env.production has restrictive permissions ($env_perms) (OK)"
        else
            warn ".env.production has permissive permissions ($env_perms), should be 600"
            issues=$((issues + 1))
        fi
    else
        warn ".env.production not found (required for production deployment)"
        issues=$((issues + 1))
    fi

    if [ -f .trivy.yml ]; then
        info "Trivy configuration found (.trivy.yml) (OK)"
    else
        warn "Trivy configuration not found (.trivy.yml)"
    fi

    section "Security Verification Summary"
    if [ "$issues" -eq 0 ]; then
        info "All security checks passed - no issues found"
    else
        warn "Security verification completed with $issues issue(s)"
    fi

    return $issues
}

generate_security_report() {
    section "Generating Security Report"
    local report_file="security-report-$(date +%Y%m%d-%H%M%S).txt"

    {
        echo "AgentOS Docker Security Report"
        echo "Generated: $(date -Iseconds)"
        echo "================================"
        echo ""

        echo "=== Running Containers ==="
        docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "No containers running"
        echo ""

        echo "=== Container Security Details ==="
        for cid in $(docker ps -q 2>/dev/null); do
            local name
            name=$(docker inspect --format '{{.Name}}' "$cid" 2>/dev/null | tr -d '/')
            echo "--- $name ---"
            echo "  User: $(docker exec "$cid" whoami 2>/dev/null || echo 'unknown')"
            echo "  Privileged: $(docker inspect --format '{{.HostConfig.Privileged}}' "$cid" 2>/dev/null)"
            echo "  ReadOnly FS: $(docker inspect --format '{{.HostConfig.ReadonlyRootfs}}' "$cid" 2>/dev/null)"
            echo "  SecurityOpt: $(docker inspect --format '{{.HostConfig.SecurityOpt}}' "$cid" 2>/dev/null)"
            echo "  CapAdd: $(docker inspect --format '{{.HostConfig.CapAdd}}' "$cid" 2>/dev/null)"
            echo "  CapDrop: $(docker inspect --format '{{.HostConfig.CapDrop}}' "$cid" 2>/dev/null)"
            echo "  NetworkMode: $(docker inspect --format '{{.HostConfig.NetworkMode}}' "$cid" 2>/dev/null)"
            echo ""
        done

        echo "=== Docker Daemon Info ==="
        docker info --format '{{.SecurityOptions}}' 2>/dev/null || echo "Could not retrieve daemon info"
        echo ""

        echo "=== Network Isolation ==="
        docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}" 2>/dev/null || echo "Could not list networks"
        echo ""

    } > "$report_file"

    info "Security report saved to: $report_file"
}

usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  all         Apply all hardening measures (default)"
    echo "  kernel      Harden kernel container only"
    echo "  gateway     Harden gateway container only"
    echo "  redis       Harden Redis container only"
    echo "  postgres    Harden PostgreSQL container only"
    echo "  daemon      Check Docker daemon security configuration"
    echo "  trust       Verify Docker Content Trust configuration"
    echo "  scan        Scan images for vulnerabilities (requires trivy)"
    echo "  verify      Run comprehensive security verification"
    echo "  report      Generate detailed security report"
    echo "  help        Show this help message"
}

main() {
    local cmd="${1:-all}"

    check_docker_running

    case "$cmd" in
        all)
            harden_kernel
            harden_gateway
            harden_redis
            harden_postgres
            harden_docker_daemon || true
            verify_security
            ;;
        kernel)
            harden_kernel
            ;;
        gateway)
            harden_gateway
            ;;
        redis)
            harden_redis
            ;;
        postgres)
            harden_postgres
            ;;
        daemon)
            harden_docker_daemon
            ;;
        trust)
            verify_image_signatures
            ;;
        scan)
            scan_vulnerabilities
            ;;
        verify)
            verify_security
            ;;
        report)
            generate_security_report
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            error "Unknown command: $cmd"
            usage
            exit 1
            ;;
    esac
}

main "$@"
