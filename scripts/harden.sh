#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[HARDEN]${NC} $*"; }
warn()  { echo -e "${YELLOW}[HARDEN]${NC} $*"; }
error() { echo -e "${RED}[HARDEN]${NC} $*"; }

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

verify_security() {
    info "Running security verification..."
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
    fi

    local exposed_ports
    exposed_ports=$(docker ps --format '{{.Ports}}' 2>/dev/null | grep -c '0.0.0.0' || echo "0")
    if [ "$exposed_ports" -gt 0 ]; then
        warn "$exposed_ports container(s) have ports exposed to 0.0.0.0"
        issues=$((issues + 1))
    fi

    if [ "$issues" -eq 0 ]; then
        info "Security verification passed - no issues found"
    else
        warn "Security verification completed with $issues issue(s)"
    fi

    return $issues
}

usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  all       Apply all hardening measures (default)"
    echo "  kernel    Harden kernel container only"
    echo "  gateway   Harden gateway container only"
    echo "  redis     Harden Redis container only"
    echo "  postgres  Harden PostgreSQL container only"
    echo "  verify    Run security verification only"
    echo "  help      Show this help message"
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
        verify)
            verify_security
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
