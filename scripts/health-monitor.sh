#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
SERVER_URL="${SERVER_URL:-https://localhost:8443}"
CA_CERTS_DIR="./ca/certs"
REFRESH_INTERVAL=5

# Function to display usage
usage() {
    echo -e "${BLUE}Health Monitor - Real-time host health dashboard${NC}"
    echo ""
    echo -e "${YELLOW}Usage: $0 [OPTIONS]${NC}"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  -s, --server URL         Server URL (default: https://localhost:8443)"
    echo "  -c, --certs-dir DIR      Certificates directory (default: ./ca/certs)"
    echo "  -i, --interval SEC       Refresh interval in seconds (default: 5)"
    echo "  -o, --once              Run once and exit (no continuous monitoring)"
    echo "  -h, --host SERVICE:INST  Monitor specific host only"
    echo "  -f, --format FORMAT     Output format: table|json|compact (default: table)"
    echo "  --help                  Show this help message"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  $0                                    # Monitor all hosts"
    echo "  $0 -h web-service:web-01             # Monitor specific host"
    echo "  $0 -o -f json                        # Single JSON dump"
    echo "  $0 -i 10                             # Refresh every 10 seconds"
}

# Parse command line arguments
RUN_ONCE=false
SPECIFIC_HOST=""
OUTPUT_FORMAT="table"

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--server)
            SERVER_URL="$2"
            shift 2
            ;;
        -c|--certs-dir)
            CA_CERTS_DIR="$2"
            shift 2
            ;;
        -i|--interval)
            REFRESH_INTERVAL="$2"
            shift 2
            ;;
        -o|--once)
            RUN_ONCE=true
            shift
            ;;
        -h|--host)
            SPECIFIC_HOST="$2"
            shift 2
            ;;
        -f|--format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Certificate files
CERT_FILE="${CA_CERTS_DIR}/test-client.crt"
KEY_FILE="${CA_CERTS_DIR}/test-client.key"
CA_FILE="${CA_CERTS_DIR}/root_ca.crt"

# Verify certificate files exist
for file in "$CERT_FILE" "$KEY_FILE" "$CA_FILE"; do
    if [[ ! -f "$file" ]]; then
        echo -e "${RED}Error: Certificate file not found: $file${NC}"
        echo -e "${YELLOW}Please run ./scripts/init-ca.sh first${NC}"
        exit 1
    fi
done

# Function to make authenticated HTTP request
make_request() {
    local url="$1"

    curl --silent --show-error \
         --cert "$CERT_FILE" \
         --key "$KEY_FILE" \
         --cacert "$CA_FILE" \
         --connect-timeout 10 \
         --max-time 30 \
         "$url" 2>/dev/null || echo '{"error": "connection_failed"}'
}

# Function to get health status color
get_status_color() {
    local status="$1"
    case "$status" in
        "healthy") echo -e "${GREEN}$status${NC}" ;;
        "degraded") echo -e "${YELLOW}$status${NC}" ;;
        "unhealthy") echo -e "${RED}$status${NC}" ;;
        *) echo -e "${CYAN}$status${NC}" ;;
    esac
}

# Function to get health score color
get_score_color() {
    local score="$1"
    if [[ "$score" -ge 80 ]]; then
        echo -e "${GREEN}$score${NC}"
    elif [[ "$score" -ge 60 ]]; then
        echo -e "${YELLOW}$score${NC}"
    else
        echo -e "${RED}$score${NC}"
    fi
}

# Function to format percentage with color
format_percentage() {
    local value="$1"
    local threshold1="$2"  # degraded threshold
    local threshold2="$3"  # critical threshold

    local formatted=$(printf "%.1f%%" "$value")

    if (( $(echo "$value < $threshold1" | bc -l) )); then
        echo -e "${GREEN}$formatted${NC}"
    elif (( $(echo "$value < $threshold2" | bc -l) )); then
        echo -e "${YELLOW}$formatted${NC}"
    else
        echo -e "${RED}$formatted${NC}"
    fi
}

# Function to display host health in table format
display_host_health_table() {
    local host_data="$1"

    local service_name=$(echo "$host_data" | jq -r '.service_name')
    local instance_name=$(echo "$host_data" | jq -r '.instance_name')
    local last_seen=$(echo "$host_data" | jq -r '.last_seen')
    local latest_status=$(echo "$host_data" | jq -r '.statuses[-1]')

    if [[ "$latest_status" == "null" ]]; then
        echo -e "${RED}No status data available for $service_name:$instance_name${NC}"
        return
    fi

    local status=$(echo "$latest_status" | jq -r '.status')
    local ip_address=$(echo "$latest_status" | jq -r '.ip_address')
    local client_cn=$(echo "$latest_status" | jq -r '.client_cn // "N/A"')
    local health_metrics=$(echo "$latest_status" | jq -r '.health_metrics')

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Host: ${MAGENTA}$service_name:$instance_name${NC}"
    echo -e "${CYAN}IP: ${NC}$ip_address  ${CYAN}Certificate: ${NC}$client_cn"
    echo -e "${CYAN}Last Seen: ${NC}$(date -d "$last_seen" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$last_seen")"
    echo -e "${CYAN}Status: $(get_status_color "$status")${NC}"

    if [[ "$health_metrics" != "null" ]]; then
        local cpu_usage=$(echo "$health_metrics" | jq -r '.cpu_usage')
        local memory_usage=$(echo "$health_metrics" | jq -r '.memory_usage')
        local disk_usage=$(echo "$health_metrics" | jq -r '.disk_usage')
        local network_ok=$(echo "$health_metrics" | jq -r '.network_ok')
        local overall_score=$(echo "$health_metrics" | jq -r '.overall_score')
        local checks=$(echo "$health_metrics" | jq -r '.checks')

        echo ""
        echo -e "${YELLOW}System Metrics:${NC}"
        echo -e "  CPU Usage:    $(format_percentage "$cpu_usage" 80 90)"
        echo -e "  Memory Usage: $(format_percentage "$memory_usage" 85 95)"
        echo -e "  Disk Usage:   $(format_percentage "$disk_usage" 85 95)"

        if [[ "$network_ok" == "true" ]]; then
            echo -e "  Network:      ${GREEN}OK${NC}"
        else
            echo -e "  Network:      ${RED}Failed${NC}"
        fi

        echo -e "  Health Score: $(get_score_color "$overall_score")/100"

        # Display individual health checks
        if [[ "$checks" != "null" ]] && [[ $(echo "$checks" | jq 'length') -gt 0 ]]; then
            echo ""
            echo -e "${YELLOW}Health Checks:${NC}"
            echo "$checks" | jq -r '.[] | "  \(.name): \(.status) \(if .value then "(\(.value))" else "" end) \(if .message then "- \(.message)" else "" end)"' | while read -r line; do
                if [[ "$line" =~ "healthy" ]]; then
                    echo -e "  ${GREEN}✓${NC} ${line/healthy/}"
                elif [[ "$line" =~ "degraded" ]]; then
                    echo -e "  ${YELLOW}⚠${NC} ${line/degraded/}"
                elif [[ "$line" =~ "unhealthy" ]]; then
                    echo -e "  ${RED}✗${NC} ${line/unhealthy/}"
                else
                    echo -e "  ${CYAN}•${NC} $line"
                fi
            done
        fi
    else
        echo -e "${YELLOW}No detailed health metrics available${NC}"
    fi

    echo ""
}

# Function to display compact format
display_host_health_compact() {
    local host_data="$1"

    local service_name=$(echo "$host_data" | jq -r '.service_name')
    local instance_name=$(echo "$host_data" | jq -r '.instance_name')
    local latest_status=$(echo "$host_data" | jq -r '.statuses[-1]')

    if [[ "$latest_status" == "null" ]]; then
        printf "%-25s %-15s %s\n" "$service_name:$instance_name" "NO_DATA" "No status available"
        return
    fi

    local status=$(echo "$latest_status" | jq -r '.status')
    local health_metrics=$(echo "$latest_status" | jq -r '.health_metrics')
    local ip_address=$(echo "$latest_status" | jq -r '.ip_address')

    if [[ "$health_metrics" != "null" ]]; then
        local cpu=$(echo "$health_metrics" | jq -r '.cpu_usage')
        local mem=$(echo "$health_metrics" | jq -r '.memory_usage')
        local disk=$(echo "$health_metrics" | jq -r '.disk_usage')
        local score=$(echo "$health_metrics" | jq -r '.overall_score')

        printf "%-25s $(get_status_color "%-10s") CPU: %5.1f%% MEM: %5.1f%% DISK: %5.1f%% Score: $(get_score_color "%3s")/100 %s\n" \
               "$service_name:$instance_name" "$status" "$cpu" "$mem" "$disk" "$score" "$ip_address"
    else
        printf "%-25s $(get_status_color "%-10s") %s (no metrics)\n" "$service_name:$instance_name" "$status" "$ip_address"
    fi
}

# Function to get and display health data
display_health_dashboard() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ "$OUTPUT_FORMAT" == "table" ]]; then
        clear
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║${NC} ${MAGENTA}Host Discovery Service - Health Dashboard${NC}                                 ${BLUE}║${NC}"
        echo -e "${BLUE}║${NC} Updated: $timestamp                                              ${BLUE}║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
    elif [[ "$OUTPUT_FORMAT" == "compact" ]]; then
        clear
        echo -e "${BLUE}Health Dashboard - $timestamp${NC}"
        echo -e "${BLUE}$(printf '=%.0s' {1..80})${NC}"
        printf "%-25s %-12s %-50s %s\n" "HOST" "STATUS" "METRICS" "IP"
        echo -e "${BLUE}$(printf '-%.0s' {1..80})${NC}"
    fi

    # Get hosts data
    local url
    if [[ -n "$SPECIFIC_HOST" ]]; then
        local service_name="${SPECIFIC_HOST%:*}"
        local instance_name="${SPECIFIC_HOST#*:}"
        url="${SERVER_URL}/api/v1/hosts/${service_name}/${instance_name}"

        local host_data=$(make_request "$url")

        if echo "$host_data" | jq -e '.error' >/dev/null 2>&1; then
            echo -e "${RED}Error: Failed to fetch host data${NC}"
            return 1
        fi

        if [[ "$OUTPUT_FORMAT" == "json" ]]; then
            echo "$host_data" | jq '.'
        elif [[ "$OUTPUT_FORMAT" == "compact" ]]; then
            display_host_health_compact "$host_data"
        else
            display_host_health_table "$host_data"
        fi
    else
        url="${SERVER_URL}/api/v1/hosts"
        local hosts_data=$(make_request "$url")

        if echo "$hosts_data" | jq -e '.error' >/dev/null 2>&1; then
            echo -e "${RED}Error: Failed to fetch hosts data${NC}"
            return 1
        fi

        local total_hosts=$(echo "$hosts_data" | jq -r '.total // 0')

        if [[ "$OUTPUT_FORMAT" == "json" ]]; then
            echo "$hosts_data" | jq '.'
        elif [[ "$total_hosts" -eq 0 ]]; then
            echo -e "${YELLOW}No hosts registered${NC}"
        else
            if [[ "$OUTPUT_FORMAT" == "table" ]]; then
                echo -e "${CYAN}Total Hosts: $total_hosts${NC}"
                echo ""
            fi

            echo "$hosts_data" | jq -c '.hosts[]' | while read -r host; do
                if [[ "$OUTPUT_FORMAT" == "compact" ]]; then
                    display_host_health_compact "$host"
                else
                    display_host_health_table "$host"
                fi
            done
        fi
    fi

    if [[ "$OUTPUT_FORMAT" == "compact" ]]; then
        echo -e "${BLUE}$(printf '=%.0s' {1..80})${NC}"
    fi
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()

    if ! command -v curl >/dev/null 2>&1; then
        missing_deps+=("curl")
    fi

    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
    fi

    if ! command -v bc >/dev/null 2>&1; then
        missing_deps+=("bc")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${RED}Missing required dependencies: ${missing_deps[*]}${NC}"
        echo -e "${YELLOW}Please install them:${NC}"
        echo "  Ubuntu/Debian: sudo apt-get install curl jq bc"
        echo "  CentOS/RHEL:   sudo yum install curl jq bc"
        echo "  macOS:         brew install curl jq bc"
        exit 1
    fi
}

# Main execution
main() {
    check_dependencies

    if [[ "$RUN_ONCE" == true ]]; then
        display_health_dashboard
        exit 0
    fi

    # Continuous monitoring
    echo -e "${YELLOW}Starting health monitor (press Ctrl+C to exit)...${NC}"
    echo -e "${CYAN}Refresh interval: ${REFRESH_INTERVAL}s${NC}"
    echo ""

    # Trap Ctrl+C for clean exit
    trap 'echo -e "\n${YELLOW}Health monitor stopped${NC}"; exit 0' INT

    while true; do
        display_health_dashboard

        if [[ "$OUTPUT_FORMAT" == "table" ]]; then
            echo -e "${CYAN}Press Ctrl+C to exit. Next refresh in ${REFRESH_INTERVAL}s...${NC}"
        fi

        sleep "$REFRESH_INTERVAL"
    done
}

# Run main function
main "$@"
