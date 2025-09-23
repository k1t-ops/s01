#!/bin/bash



# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SERVER_URL="https://localhost:8443"
HEALTH_URL="http://localhost:8080"
CA_CERTS_DIR="./ca/certs"
TEST_SERVICE="test-service"
TEST_INSTANCE="test-instance-$(date +%s)"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Test results
PASSED=0
FAILED=0

# Function to print test result
print_result() {
    local test_name="$1"
    local result="$2"
    local message="$3"

    if [[ "$result" == "PASS" ]]; then
        echo -e "  ${GREEN}✓${NC} $test_name"
        ((PASSED++))
    else
        echo -e "  ${RED}✗${NC} $test_name: $message"
        ((FAILED++))
    fi
}

# Function to make HTTP request with client certificate
make_request() {
    local method="$1"
    local url="$2"
    local data="$3"
    local expect_success="${4:-true}"

    local cert_file="${CA_CERTS_DIR}/test-client.crt"
    local key_file="${CA_CERTS_DIR}/test-client.key"
    local ca_file="${CA_CERTS_DIR}/ca_chain.crt"

    if [[ ! -f "$cert_file" || ! -f "$key_file" || ! -f "$ca_file" ]]; then
        echo -e "${RED}Error: Required certificate files not found in $CA_CERTS_DIR${NC}"
        echo "Please run ./scripts/init-ca.sh first"
        exit 1
    fi

    local curl_args=(
        --silent
        --show-error
        --write-out "HTTP_CODE:%{http_code}\n"
        --cert "$cert_file"
        --key "$key_file"
        --insecure
        --connect-timeout 10
        --max-time 30
    )

    if [[ "$method" == "POST" ]]; then
        curl_args+=(--request POST)
        curl_args+=(--header "Content-Type: application/json")
        if [[ -n "$data" ]]; then
            curl_args+=(--data "$data")
        fi
    fi

    curl "${curl_args[@]}" "$url" 2>/dev/null || echo "HTTP_CODE:000"
}

# Function to extract HTTP status code from curl response
extract_http_code() {
    echo "$1" | grep "HTTP_CODE:" | cut -d: -f2
}

# Function to extract response body from curl response
extract_response_body() {
    echo "$1" | sed '/HTTP_CODE:/d'
}

echo -e "${BLUE}S01 Service Test Suite${NC}"
echo -e "${BLUE}============================${NC}"
echo ""

# Check if s01 server is running
echo -e "${YELLOW}Checking server status...${NC}"

# Test 1: Health check (no auth required)
echo -e "${YELLOW}1. Testing health endpoint (no auth)...${NC}"
health_response=$(curl --silent --show-error --write-out "HTTP_CODE:%{http_code}\n" --connect-timeout 5 "${HEALTH_URL}/health" 2>/dev/null || echo "HTTP_CODE:000")
health_code=$(extract_http_code "$health_response")
health_body=$(extract_response_body "$health_response")

if [[ "$health_code" == "200" ]]; then
    print_result "Health endpoint accessible" "PASS"
    echo "    Response: $health_body" | jq '.' 2>/dev/null || echo "    Response: $health_body"
else
    print_result "Health endpoint accessible" "FAIL" "HTTP $health_code"
    echo -e "${RED}Server appears to be down. Please start the server first.${NC}"
    exit 1
fi

echo ""

# Test 2: Status reporting with valid certificate
echo -e "${YELLOW}2. Testing status reporting...${NC}"

# Valid status report
status_data='{
    "service_name": "'$TEST_SERVICE'",
    "instance_name": "'$TEST_INSTANCE'",
    "status": "healthy"
}'

report_response=$(make_request "POST" "${SERVER_URL}/api/v1/report" "$status_data")
report_code=$(extract_http_code "$report_response")
report_body=$(extract_response_body "$report_response")

if [[ "$report_code" == "200" ]]; then
    print_result "Valid status report" "PASS"
else
    print_result "Valid status report" "FAIL" "HTTP $report_code - $report_body"
fi

# Test 3: Status reporting with missing fields
missing_data='{
    "service_name": "'$TEST_SERVICE'",
    "status": "healthy"
}'

missing_response=$(make_request "POST" "${SERVER_URL}/api/v1/report" "$missing_data")
missing_code=$(extract_http_code "$missing_response")

if [[ "$missing_code" == "400" ]]; then
    print_result "Reject invalid status report (missing fields)" "PASS"
else
    print_result "Reject invalid status report (missing fields)" "FAIL" "Expected HTTP 400, got $missing_code"
fi

# Test 4: Status reporting with invalid JSON
invalid_response=$(make_request "POST" "${SERVER_URL}/api/v1/report" "invalid json")
invalid_code=$(extract_http_code "$invalid_response")

if [[ "$invalid_code" == "400" ]]; then
    print_result "Reject invalid JSON" "PASS"
else
    print_result "Reject invalid JSON" "FAIL" "Expected HTTP 400, got $invalid_code"
fi

echo ""

# Test 5: Host s01
echo -e "${YELLOW}3. Testing host s01...${NC}"

# Get all hosts
hosts_response=$(make_request "GET" "${SERVER_URL}/api/v1/hosts")
hosts_code=$(extract_http_code "$hosts_response")
hosts_body=$(extract_response_body "$hosts_response")

if [[ "$hosts_code" == "200" ]]; then
    print_result "Get all hosts" "PASS"

    # Check if our test host is in the response
    if echo "$hosts_body" | jq -e ".hosts[] | select(.service_name==\"$TEST_SERVICE\" and .instance_name==\"$TEST_INSTANCE\")" >/dev/null 2>&1; then
        print_result "Test host found in s01" "PASS"
    else
        print_result "Test host found in s01" "FAIL" "Test host not found in response"
    fi
else
    print_result "Get all hosts" "FAIL" "HTTP $hosts_code - $hosts_body"
fi

# Test 6: Get specific host
host_response=$(make_request "GET" "${SERVER_URL}/api/v1/hosts/${TEST_SERVICE}/${TEST_INSTANCE}")
host_code=$(extract_http_code "$host_response")
host_body=$(extract_response_body "$host_response")

if [[ "$host_code" == "200" ]]; then
    print_result "Get specific host" "PASS"

    # Verify the response contains expected data
    service_name=$(echo "$host_body" | jq -r '.service_name' 2>/dev/null)
    instance_name=$(echo "$host_body" | jq -r '.instance_name' 2>/dev/null)

    if [[ "$service_name" == "$TEST_SERVICE" && "$instance_name" == "$TEST_INSTANCE" ]]; then
        print_result "Host data integrity" "PASS"
    else
        print_result "Host data integrity" "FAIL" "Service: $service_name, Instance: $instance_name"
    fi
else
    print_result "Get specific host" "FAIL" "HTTP $host_code - $host_body"
fi

# Test 7: Get non-existent host
notfound_response=$(make_request "GET" "${SERVER_URL}/api/v1/hosts/nonexistent/host")
notfound_code=$(extract_http_code "$notfound_response")

if [[ "$notfound_code" == "404" ]]; then
    print_result "404 for non-existent host" "PASS"
else
    print_result "404 for non-existent host" "FAIL" "Expected HTTP 404, got $notfound_code"
fi

echo ""

# Test 8: Multiple status reports (history tracking)
echo -e "${YELLOW}4. Testing status history...${NC}"

# Send multiple status reports
for status in "healthy" "degraded" "healthy"; do
    status_data='{
        "service_name": "'$TEST_SERVICE'",
        "instance_name": "'$TEST_INSTANCE'",
        "status": "'$status'"
    }'

    make_request "POST" "${SERVER_URL}/api/v1/report" "$status_data" >/dev/null
    sleep 1
done

# Get the host again and check history
history_response=$(make_request "GET" "${SERVER_URL}/api/v1/hosts/${TEST_SERVICE}/${TEST_INSTANCE}")
history_code=$(extract_http_code "$history_response")
history_body=$(extract_response_body "$history_response")

if [[ "$history_code" == "200" ]]; then
    status_count=$(echo "$history_body" | jq '.statuses | length' 2>/dev/null)
    if [[ "$status_count" -ge "3" ]]; then
        print_result "Status history tracking" "PASS"

        # Check if statuses are in chronological order
        last_timestamp=""
        chronological=true
        while IFS= read -r timestamp; do
            if [[ -n "$last_timestamp" && "$timestamp" < "$last_timestamp" ]]; then
                chronological=false
                break
            fi
            last_timestamp="$timestamp"
        done < <(echo "$history_body" | jq -r '.statuses[].timestamp' 2>/dev/null)

        if [[ "$chronological" == true ]]; then
            print_result "Chronological order" "PASS"
        else
            print_result "Chronological order" "FAIL" "Timestamps not in order"
        fi
    else
        print_result "Status history tracking" "FAIL" "Expected >= 3 statuses, got $status_count"
    fi
else
    print_result "Status history tracking" "FAIL" "HTTP $history_code"
fi

echo ""

# Test 9: Certificate validation
echo -e "${YELLOW}5. Testing certificate validation...${NC}"

# Test without certificate (should fail)
no_cert_response=$(curl --silent --show-error --write-out "HTTP_CODE:%{http_code}\n" --insecure --connect-timeout 5 "${SERVER_URL}/api/v1/hosts" 2>/dev/null || echo "HTTP_CODE:000")
no_cert_code=$(extract_http_code "$no_cert_response")

if [[ "$no_cert_code" != "200" ]]; then
    print_result "Reject requests without client certificate" "PASS"
else
    print_result "Reject requests without client certificate" "FAIL" "Request succeeded without certificate"
fi

echo ""

# Test 10: Load test (optional)
echo -e "${YELLOW}6. Basic load test...${NC}"

load_start=$(date +%s)
load_success=0
load_total=10

for i in $(seq 1 $load_total); do
    load_data='{
        "service_name": "'$TEST_SERVICE'",
        "instance_name": "load-test-'$i'",
        "status": "healthy"
    }'

    load_response=$(make_request "POST" "${SERVER_URL}/api/v1/report" "$load_data")
    load_code=$(extract_http_code "$load_response")

    if [[ "$load_code" == "200" ]]; then
        ((load_success++))
    fi
done

load_end=$(date +%s)
load_duration=$((load_end - load_start))

if [[ "$load_success" == "$load_total" ]]; then
    print_result "Load test ($load_total requests in ${load_duration}s)" "PASS"
else
    print_result "Load test" "FAIL" "$load_success/$load_total requests succeeded"
fi

echo ""

# Summary
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}============${NC}"
echo -e "Tests passed: ${GREEN}$PASSED${NC}"
echo -e "Tests failed: ${RED}$FAILED${NC}"
echo -e "Total tests: $((PASSED + FAILED))"

if [[ $FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}All tests passed! 🎉${NC}"
    echo -e "${YELLOW}Your s01 service is working correctly.${NC}"
else
    echo -e "\n${RED}Some tests failed. 😞${NC}"
    echo -e "${YELLOW}Please check the server logs and configuration.${NC}"
fi

echo ""
echo -e "${YELLOW}Additional Information:${NC}"
echo "  Server URL: $SERVER_URL"
echo "  Test Service: $TEST_SERVICE"
echo "  Test Instance: $TEST_INSTANCE"
echo "  Certificate Path: $CA_CERTS_DIR"

# Show current hosts (if available)
if [[ "$hosts_code" == "200" ]]; then
    echo ""
    echo -e "${YELLOW}Current registered hosts:${NC}"
    echo "$hosts_body" | jq '.hosts[] | {service_name, instance_name, last_seen}' 2>/dev/null || echo "Unable to parse host data"
fi

exit $FAILED
