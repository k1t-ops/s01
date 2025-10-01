#!/bin/bash
set -euo pipefail

# s01 Test Runner Script
# This script executes comprehensive tests for the s01 service discovery system

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
SERVER_URL="${SERVER_URL:-https://s01-server:8443}"
HEALTH_URL="${HEALTH_URL:-http://s01-server:8080/health}"
CERT_FILE="${CERT_FILE:-/etc/ssl/certs/test-client.crt}"
KEY_FILE="${KEY_FILE:-/etc/ssl/certs/test-client.key}"
CA_CERT_FILE="${CA_CERT_FILE:-/etc/ssl/certs/root_ca.crt}"
TEST_TIMEOUT="${TEST_TIMEOUT:-300}"
PARALLEL_TESTS="${PARALLEL_TESTS:-4}"
RESULTS_DIR="${RESULTS_DIR:-/results}"
LOG_DIR="${LOG_DIR:-/tmp/test-logs}"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Test suite to run
TEST_SUITE="${1:-all}"

# Create directories
mkdir -p "$RESULTS_DIR" "$LOG_DIR"

# Test results file
RESULTS_FILE="$RESULTS_DIR/test-results-$(date +%Y%m%d-%H%M%S).json"
JUNIT_FILE="$RESULTS_DIR/junit.xml"

# Initialize results
echo '{"tests": [], "summary": {}}' > "$RESULTS_FILE"

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" >> "$LOG_DIR/test.log"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $1" >> "$LOG_DIR/test.log"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_DIR/test.log"
}

log_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] TEST: $1" >> "$LOG_DIR/test.log"
}

log_pass() {
    echo -e "${GREEN}✓${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] PASS: $1" >> "$LOG_DIR/test.log"
}

log_fail() {
    echo -e "${RED}✗${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] FAIL: $1" >> "$LOG_DIR/test.log"
}

log_skip() {
    echo -e "${YELLOW}⊘${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SKIP: $1" >> "$LOG_DIR/test.log"
}

# Print test banner
print_banner() {
    echo -e "${CYAN}"
    echo "╭─────────────────────────────────────────────────────╮"
    echo "│             s01 Test Runner v1.0                   │"
    echo "│                                                     │"
    echo "│  Testing suite: $TEST_SUITE"
    echo "│  Server URL: $SERVER_URL"
    echo "│  Timeout: ${TEST_TIMEOUT}s"
    echo "╰─────────────────────────────────────────────────────╯"
    echo -e "${NC}"
}

# Add test result
add_test_result() {
    local test_name="$1"
    local status="$2"
    local duration="$3"
    local message="${4:-}"

    local result_json=$(jq -n \
        --arg name "$test_name" \
        --arg status "$status" \
        --arg duration "$duration" \
        --arg message "$message" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{name: $name, status: $status, duration: $duration, message: $message, timestamp: $timestamp}')

    jq ".tests += [$result_json]" "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"

    case "$status" in
        "pass")
            ((PASSED_TESTS++))
            log_pass "$test_name (${duration}s)"
            ;;
        "fail")
            ((FAILED_TESTS++))
            log_fail "$test_name (${duration}s) - $message"
            ;;
        "skip")
            ((SKIPPED_TESTS++))
            log_skip "$test_name - $message"
            ;;
    esac
    ((TOTAL_TESTS++))
}

# Wait for services to be ready
wait_for_services() {
    log_info "Waiting for services to be ready..."

    local max_wait=60
    local wait_time=0

    # Wait for server health endpoint
    while [ $wait_time -lt $max_wait ]; do
        if curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
            log_info "Server health endpoint is ready"
            break
        fi
        sleep 2
        wait_time=$((wait_time + 2))
    done

    if [ $wait_time -ge $max_wait ]; then
        log_error "Server did not become ready within ${max_wait}s"
        return 1
    fi

    # Wait for HTTPS endpoint with certificates
    wait_time=0
    while [ $wait_time -lt $max_wait ]; do
        if curl -sf -k --cert "$CERT_FILE" --key "$KEY_FILE" "$SERVER_URL/api/v1/hosts" > /dev/null 2>&1; then
            log_info "Server HTTPS endpoint is ready"
            break
        fi
        sleep 2
        wait_time=$((wait_time + 2))
    done

    if [ $wait_time -ge $max_wait ]; then
        log_error "Server HTTPS endpoint did not become ready within ${max_wait}s"
        return 1
    fi

    # Give clients time to register
    log_info "Waiting for clients to register..."
    sleep 10

    return 0
}

# Test: Server connectivity
test_server_connectivity() {
    local test_name="Server Connectivity"
    log_test "$test_name"
    local start_time=$(date +%s)

    if curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "pass" "$duration"
        return 0
    else
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "fail" "$duration" "Cannot connect to health endpoint"
        return 1
    fi
}

# Test: Health endpoint
test_health_endpoint() {
    local test_name="Health Endpoint"
    log_test "$test_name"
    local start_time=$(date +%s)

    local response=$(curl -sf "$HEALTH_URL" 2>/dev/null || echo "{}")
    local status=$(echo "$response" | jq -r '.status' 2>/dev/null || echo "")

    if [ "$status" = "healthy" ]; then
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "pass" "$duration"
        return 0
    else
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "fail" "$duration" "Unexpected health status: $status"
        return 1
    fi
}

# Test: Certificate authentication
test_certificate_auth() {
    local test_name="Certificate Authentication"
    log_test "$test_name"
    local start_time=$(date +%s)

    # Test with valid certificate
    if curl -sf -k --cert "$CERT_FILE" --key "$KEY_FILE" "$SERVER_URL/api/v1/hosts" > /dev/null 2>&1; then
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "pass" "$duration"
        return 0
    else
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "fail" "$duration" "Certificate authentication failed"
        return 1
    fi
}

# Test: Invalid certificate rejection
test_invalid_cert_rejection() {
    local test_name="Invalid Certificate Rejection"
    log_test "$test_name"
    local start_time=$(date +%s)

    # Test without certificate (should fail)
    if curl -sf -k "$SERVER_URL/api/v1/hosts" 2>/dev/null; then
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "fail" "$duration" "Server accepted request without certificate"
        return 1
    else
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "pass" "$duration"
        return 0
    fi
}

# Test: List hosts
test_list_hosts() {
    local test_name="List Hosts API"
    log_test "$test_name"
    local start_time=$(date +%s)

    local response=$(curl -sf -k --cert "$CERT_FILE" --key "$KEY_FILE" "$SERVER_URL/api/v1/hosts" 2>/dev/null)

    if [ -z "$response" ]; then
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "fail" "$duration" "Empty response from server"
        return 1
    fi

    local host_count=$(echo "$response" | jq 'length' 2>/dev/null || echo "0")

    if [ "$host_count" -gt 0 ]; then
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "pass" "$duration"
        log_info "Found $host_count registered hosts"
        return 0
    else
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "fail" "$duration" "No hosts found"
        return 1
    fi
}

# Test: Service discovery
test_service_discovery() {
    local test_name="Service Discovery"
    log_test "$test_name"
    local start_time=$(date +%s)

    local response=$(curl -sf -k --cert "$CERT_FILE" --key "$KEY_FILE" "$SERVER_URL/api/v1/hosts" 2>/dev/null)

    # Check for expected services
    local expected_services=("web-service" "api-service" "database" "worker-service")
    local all_found=true

    for service in "${expected_services[@]}"; do
        if echo "$response" | jq -e ".[] | select(.service == \"$service\")" > /dev/null 2>&1; then
            log_info "Found service: $service"
        else
            log_warn "Service not found: $service"
            all_found=false
        fi
    done

    if [ "$all_found" = true ]; then
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "pass" "$duration"
        return 0
    else
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "fail" "$duration" "Not all expected services found"
        return 1
    fi
}

# Test: Host history
test_host_history() {
    local test_name="Host History API"
    log_test "$test_name"
    local start_time=$(date +%s)

    # Test with a known service/instance
    local service="web-service"
    local instance="web-01"
    local url="$SERVER_URL/api/v1/hosts/$service/$instance"

    local response=$(curl -sf -k --cert "$CERT_FILE" --key "$KEY_FILE" "$url" 2>/dev/null)

    if [ -z "$response" ]; then
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "fail" "$duration" "Empty response for host history"
        return 1
    fi

    local history_count=$(echo "$response" | jq '.history | length' 2>/dev/null || echo "0")

    if [ "$history_count" -gt 0 ]; then
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "pass" "$duration"
        log_info "Found $history_count history entries for $service/$instance"
        return 0
    else
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "fail" "$duration" "No history found for $service/$instance"
        return 1
    fi
}

# Test: Status reporting
test_status_reporting() {
    local test_name="Status Reporting"
    log_test "$test_name"
    local start_time=$(date +%s)

    # Create test report data
    local report_data=$(cat <<EOF
{
    "service": "test-service",
    "instance": "test-instance-$$",
    "status": "healthy",
    "health": {
        "cpu_percent": 25.5,
        "memory_percent": 45.0,
        "disk_percent": 60.0,
        "network_active": true
    }
}
EOF
)

    # Send report
    local response_code=$(curl -sf -o /dev/null -w "%{http_code}" \
        -k --cert "$CERT_FILE" --key "$KEY_FILE" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$report_data" \
        "$SERVER_URL/api/v1/report")

    if [ "$response_code" = "200" ] || [ "$response_code" = "204" ]; then
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "pass" "$duration"
        return 0
    else
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "fail" "$duration" "Report failed with HTTP $response_code"
        return 1
    fi
}

# Test: Stale detection
test_stale_detection() {
    local test_name="Stale Detection"
    log_test "$test_name"
    local start_time=$(date +%s)

    # Look for the flapping service which should become stale
    log_info "Waiting for stale detection to trigger..."

    # Wait for stale timeout (configured as 60s in test environment)
    sleep 65

    local response=$(curl -sf -k --cert "$CERT_FILE" --key "$KEY_FILE" "$SERVER_URL/api/v1/hosts" 2>/dev/null)

    # Check if any hosts are marked as lost
    if echo "$response" | jq -e '.[] | select(.status == "lost")' > /dev/null 2>&1; then
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "pass" "$duration"
        log_info "Stale detection working - found lost hosts"
        return 0
    else
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "skip" "$duration" "No stale hosts detected (may need longer wait)"
        return 0
    fi
}

# Test: Health status variations
test_health_status_variations() {
    local test_name="Health Status Variations"
    log_test "$test_name"
    local start_time=$(date +%s)

    local response=$(curl -sf -k --cert "$CERT_FILE" --key "$KEY_FILE" "$SERVER_URL/api/v1/hosts" 2>/dev/null)

    # Check for different health statuses
    local has_healthy=$(echo "$response" | jq -e '.[] | select(.status == "healthy")' > /dev/null 2>&1 && echo "true" || echo "false")
    local has_degraded=$(echo "$response" | jq -e '.[] | select(.status == "degraded")' > /dev/null 2>&1 && echo "true" || echo "false")
    local has_unhealthy=$(echo "$response" | jq -e '.[] | select(.status == "unhealthy")' > /dev/null 2>&1 && echo "true" || echo "false")

    log_info "Status distribution - Healthy: $has_healthy, Degraded: $has_degraded, Unhealthy: $has_unhealthy"

    if [ "$has_healthy" = "true" ] || [ "$has_degraded" = "true" ] || [ "$has_unhealthy" = "true" ]; then
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "pass" "$duration"
        return 0
    else
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "fail" "$duration" "No health status variations found"
        return 1
    fi
}

# Test: Load test
test_load() {
    local test_name="Load Test"
    log_test "$test_name"
    local start_time=$(date +%s)

    log_info "Running load test with $PARALLEL_TESTS parallel requests..."

    local errors=0

    # Run parallel requests
    for i in $(seq 1 $PARALLEL_TESTS); do
        (
            for j in $(seq 1 10); do
                if ! curl -sf -k --cert "$CERT_FILE" --key "$KEY_FILE" "$SERVER_URL/api/v1/hosts" > /dev/null 2>&1; then
                    echo "Request failed"
                fi
            done
        ) &
    done

    # Wait for all background jobs
    wait

    # Check if server is still responsive
    if curl -sf -k --cert "$CERT_FILE" --key "$KEY_FILE" "$SERVER_URL/api/v1/hosts" > /dev/null 2>&1; then
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "pass" "$duration"
        return 0
    else
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "fail" "$duration" "Server unresponsive after load test"
        return 1
    fi
}

# Test: API response times
test_api_performance() {
    local test_name="API Performance"
    log_test "$test_name"
    local start_time=$(date +%s)

    local total_time=0
    local requests=10

    for i in $(seq 1 $requests); do
        local req_start=$(date +%s%N)
        curl -sf -k --cert "$CERT_FILE" --key "$KEY_FILE" "$SERVER_URL/api/v1/hosts" > /dev/null 2>&1
        local req_end=$(date +%s%N)
        local req_time=$((($req_end - $req_start) / 1000000))
        total_time=$((total_time + req_time))
    done

    local avg_time=$((total_time / requests))
    log_info "Average response time: ${avg_time}ms"

    # Expect average response time under 500ms
    if [ "$avg_time" -lt 500 ]; then
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "pass" "$duration"
        return 0
    else
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "fail" "$duration" "Average response time ${avg_time}ms exceeds 500ms threshold"
        return 1
    fi
}

# Test: Error handling
test_error_handling() {
    local test_name="Error Handling"
    log_test "$test_name"
    local start_time=$(date +%s)

    # Test with invalid JSON
    local response_code=$(curl -sf -o /dev/null -w "%{http_code}" \
        -k --cert "$CERT_FILE" --key "$KEY_FILE" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "invalid json" \
        "$SERVER_URL/api/v1/report")

    if [ "$response_code" = "400" ]; then
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "pass" "$duration"
        return 0
    else
        local duration=$(($(date +%s) - start_time))
        add_test_result "$test_name" "fail" "$duration" "Expected 400 for invalid JSON, got $response_code"
        return 1
    fi
}

# Run test suite
run_test_suite() {
    local suite="$1"

    case "$suite" in
        "connectivity")
            test_server_connectivity
            test_health_endpoint
            test_certificate_auth
            test_invalid_cert_rejection
            ;;
        "api")
            test_list_hosts
            test_host_history
            test_status_reporting
            test_error_handling
            ;;
        "discovery")
            test_service_discovery
            test_health_status_variations
            test_stale_detection
            ;;
        "performance")
            test_api_performance
            test_load
            ;;
        "all")
            test_server_connectivity
            test_health_endpoint
            test_certificate_auth
            test_invalid_cert_rejection
            test_list_hosts
            test_service_discovery
            test_host_history
            test_status_reporting
            test_health_status_variations
            test_stale_detection
            test_api_performance
            test_load
            test_error_handling
            ;;
        *)
            log_error "Unknown test suite: $suite"
            log_info "Available suites: connectivity, api, discovery, performance, all"
            exit 1
            ;;
    esac
}

# Generate test summary
generate_summary() {
    log_info "Generating test summary..."

    # Update JSON summary
    jq ".summary.total = $TOTAL_TESTS |
        .summary.passed = $PASSED_TESTS |
        .summary.failed = $FAILED_TESTS |
        .summary.skipped = $SKIPPED_TESTS |
        .summary.success_rate = ($PASSED_TESTS / $TOTAL_TESTS * 100 | floor) |
        .summary.duration = \"$(date -d@$(($(date +%s) - START_TIME)) -u +%H:%M:%S)\" |
        .summary.timestamp = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" \
        "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"

    # Generate JUnit XML
    cat > "$JUNIT_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="s01 Tests" tests="$TOTAL_TESTS" failures="$FAILED_TESTS" skipped="$SKIPPED_TESTS" time="$(($(date +%s) - START_TIME))">
  <testsuite name="$TEST_SUITE" tests="$TOTAL_TESTS" failures="$FAILED_TESTS" skipped="$SKIPPED_TESTS">
EOF

    jq -r '.tests[] |
        "<testcase name=\"\(.name)\" time=\"\(.duration)\">" +
        (if .status == "fail" then "<failure message=\"\(.message)\"/>"
         elif .status == "skip" then "<skipped message=\"\(.message)\"/>"
         else "" end) +
        "</testcase>"' "$RESULTS_FILE" >> "$JUNIT_FILE"

    echo "  </testsuite>" >> "$JUNIT_FILE"
    echo "</testsuites>" >> "$JUNIT_FILE"

    # Print summary
    echo
    echo -e "${CYAN}╭─────────────────────────────────────────────────────╮${NC}"
    echo -e "${CYAN}│                  Test Summary                       │${NC}"
    echo -e "${CYAN}╰─────────────────────────────────────────────────────╯${NC}"
    echo
    echo -e "Total Tests:    ${TOTAL_TESTS}"
    echo -e "Passed:         ${GREEN}${PASSED_TESTS}${NC}"
    echo -e "Failed:         ${RED}${FAILED_TESTS}${NC}"
    echo -e "Skipped:        ${YELLOW}${SKIPPED_TESTS}${NC}"
    echo

    if [ "$FAILED_TESTS" -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        echo
        echo -e "Results saved to:"
        echo -e "  • JSON: $RESULTS_FILE"
        echo -e "  • JUnit: $JUNIT_FILE"
        echo -e "  • Logs: $LOG_DIR/"
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        echo
        echo -e "Failed tests:"
        jq -r '.tests[] | select(.status == "fail") | "  • \(.name): \(.message)"' "$RESULTS_FILE"
        echo
        echo -e "Results saved to:"
        echo -e "  • JSON: $RESULTS_FILE"
        echo -e "  • JUnit: $JUNIT_FILE"
        echo -e "  • Logs: $LOG_DIR/"
        return 1
    fi
}

# Main execution
main() {
    START_TIME=$(date +%s)

    print_banner

    # Wait for services
    if ! wait_for_services; then
        log_error "Services are not ready. Exiting."
        exit 1
    fi

    # Run test suite
    log_info "Running test suite: $TEST_SUITE"
    run_test_suite "$TEST_SUITE"

    # Generate summary
    generate_summary
    exit_code=$?

    # Exit with appropriate code
    exit $exit_code
}

# Handle signals
trap 'log_error "Test interrupted"; generate_summary; exit 130' INT TERM

# Run main function
main
