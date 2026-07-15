#!/bin/bash
# =============================================================================
# AgentRT Docker Health Check Script
# 版本: 0.1.0
# 用途: 检查所有AgentRT服务的健康状态
#
# 使用方法:
#   ./scripts/healthcheck.sh              # 基本检查
#   ./scripts/healthcheck.sh --json       # JSON输出
#   ./scripts/healthcheck.sh --verbose    # 详细输出
#   ./scripts/healthcheck.sh --service kernel  # 检查单个服务
# =============================================================================

set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
COMPOSE_PROJECT="${COMPOSE_PROJECT_NAME:-agentrt}"
TIMEOUT=5
RETRIES=3
OUTPUT_FORMAT="text"
TARGET_SERVICE=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --json) OUTPUT_FORMAT="json"; shift ;;
            --verbose) VERBOSE=1; shift ;;
            --service) TARGET_SERVICE="$2"; shift 2 ;;
            --timeout) TIMEOUT="$2"; shift 2 ;;
            --compose-file) COMPOSE_FILE="$2"; shift 2 ;;
            -h|--help)
                echo "Usage: $0 [--json] [--verbose] [--service NAME] [--timeout SECONDS]"
                exit 0
                ;;
            *) shift ;;
        esac
    done
}

check_service_health() {
    local service=$1
    local container_name="${COMPOSE_PROJECT}-${service}-1"
    local status="unknown"
    local http_code=0
    local response_time_ms=0

    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$" 2>/dev/null; then
        status="not_running"
        echo "{\"service\":\"${service}\",\"status\":\"${status}\",\"http_code\":0,\"response_time_ms\":0}"
        return 1
    fi

    local start_time=$(date +%s%N)

    case $service in
        kernel)
            http_code=$(curl -s -o /dev/null -w '%{http_code}' \
                --max-time ${TIMEOUT} \
                http://localhost:18080/api/v1/health 2>/dev/null || echo "000")
            ;;
        gateway)
            http_code=$(curl -s -o /dev/null -w '%{http_code}' \
                --max-time ${TIMEOUT} \
                http://localhost:18789/api/v1/health 2>/dev/null || echo "000")
            ;;
        postgres)
            if docker exec "${container_name}" pg_isready -U agentrt -d agentrt >/dev/null 2>&1; then
                http_code=200
            else
                http_code=503
            fi
            ;;
        redis)
            local health_status
            health_status=$(docker inspect --format='{{.State.Health.Status}}' "${container_name}" 2>/dev/null || echo "unknown")
            if [ "$health_status" = "healthy" ]; then
                http_code=200
            elif [ "$health_status" = "unhealthy" ]; then
                http_code=503
            else
                http_code=000
            fi
            ;;
        desktop)
            http_code=$(curl -s -o /dev/null -w '%{http_code}' \
                --max-time ${TIMEOUT} \
                http://localhost:8080/ 2>/dev/null || echo "000")
            ;;
        *)
            http_code=$(docker inspect --format='{{.State.Health.Status}}' "${container_name}" 2>/dev/null || echo "unknown")
            if [ "$http_code" = "healthy" ]; then
                http_code=200
            elif [ "$http_code" = "unhealthy" ]; then
                http_code=503
            else
                http_code=000
            fi
            ;;
    esac

    local end_time=$(date +%s%N)
    response_time_ms=$(( (end_time - start_time) / 1000000 ))

    if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        status="healthy"
    elif [[ "$http_code" -eq 000 ]]; then
        status="unreachable"
    else
        status="unhealthy"
    fi

    if [ "${OUTPUT_FORMAT}" = "json" ]; then
        echo "{\"service\":\"${service}\",\"status\":\"${status}\",\"http_code\":${http_code},\"response_time_ms\":${response_time_ms}}"
    else
        printf "  %-12s %-12s HTTP %-4d %4dms\n" "${service}" "${status}" "${http_code}" "${response_time_ms}"
    fi

    [[ "$status" == "healthy" ]]
}

main() {
    parse_args "$@"

    SERVICES=("kernel" "gateway" "postgres" "redis" "desktop" "openlab" "prometheus" "grafana")

    if [ -n "$TARGET_SERVICE" ]; then
        SERVICES=("$TARGET_SERVICE")
    fi

    if [ "${OUTPUT_FORMAT}" = "json" ]; then
        echo "["
        local first=true
        for service in "${SERVICES[@]}"; do
            if [ "$first" = true ]; then first=false; else echo ","; fi
            check_service_health "$service"
        done
        echo ""
        echo "]"
    else
        echo "=== AgentRT Service Health Check ==="
        echo "Timestamp: $(date -Iseconds)"
        echo ""
        printf "  %-12s %-12s %-10s %s\n" "SERVICE" "STATUS" "HTTP" "LATENCY"
        echo "  ----------------------------------------------"

        local all_healthy=true
        for service in "${SERVICES[@]}"; do
            if ! check_service_health "$service"; then
                all_healthy=false
            fi
        done

        echo ""
        if [ "$all_healthy" = true ]; then
            echo "✅ All services healthy"
            exit 0
        else
            echo "❌ Some services unhealthy"
            exit 1
        fi
    fi
}

main "$@"
