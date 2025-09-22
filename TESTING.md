# Testing & Validation Guide

This guide covers comprehensive testing procedures for the Host Discovery Service, from development testing to production validation.

## Overview

The testing strategy covers multiple layers:
- **Unit Tests**: Individual component functionality
- **Integration Tests**: Service interaction testing  
- **Security Tests**: Certificate and authentication validation
- **Performance Tests**: Load and stress testing
- **End-to-End Tests**: Complete workflow validation
- **Production Tests**: Live system validation

## Quick Test Suite

### Run All Tests
```bash
# Complete test suite (13 automated tests)
make test

# Expected output:
# ✓ Health endpoint accessible
# ✓ Valid status report  
# ✓ Reject invalid status report
# ✓ Get all hosts
# ✓ Certificate validation
# ... (13 tests total)
```

### Health Check
```bash
# Quick system health verification
make health

# Expected output:
# Service Health:
#   Discovery Server: ok
#   Step-CA: UP
```

## Detailed Test Categories

## 1. Automated Test Suite

### Core Functionality Tests
The main test script (`scripts/test-discovery.sh`) validates:

**Status Reporting Tests**
```bash
# Test 1: Valid status report
curl -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  -X POST -H "Content-Type: application/json" \
  -d '{"service_name":"test","instance_name":"01","status":"healthy"}' \
  https://localhost:8443/api/v1/report

# Expected: {"status":"ok"}
```

**Discovery Tests**
```bash
# Test 2: Get all hosts
curl -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  https://localhost:8443/api/v1/hosts

# Expected: JSON with hosts array and total count
```

**Validation Tests**
```bash
# Test 3: Reject invalid requests
curl -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  -X POST -H "Content-Type: application/json" \
  -d '{"invalid":"data"}' \
  https://localhost:8443/api/v1/report

# Expected: HTTP 400 Bad Request
```

### Run Individual Test Categories
```bash
# Run with debugging enabled
DEBUG=1 ./scripts/test-discovery.sh

# Test specific functionality
./scripts/test-discovery.sh --test-category=status-reporting
./scripts/test-discovery.sh --test-category=discovery
./scripts/test-discovery.sh --test-category=security
```

## 2. Security Testing

### Certificate Validation
```bash
# Test certificate chain validity
openssl verify -CAfile ca/certs/root_ca.crt ca/certs/server.crt
openssl verify -CAfile ca/certs/ca_chain.crt ca/certs/test-client.crt

# Test certificate expiration
openssl x509 -in ca/certs/server.crt -noout -enddate
openssl x509 -in ca/certs/test-client.crt -noout -enddate
```

### mTLS Authentication Tests
```bash
# Test 1: Request without certificate (should fail)
curl -k https://localhost:8443/api/v1/hosts
# Expected: Connection terminated or TLS handshake error

# Test 2: Request with invalid certificate (should fail)  
curl -k --cert /etc/ssl/certs/ssl-cert-snakeoil.pem --key /etc/ssl/private/ssl-cert-snakeoil.key \
  https://localhost:8443/api/v1/hosts
# Expected: TLS handshake error

# Test 3: Request with valid certificate (should succeed)
curl -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  https://localhost:8443/api/v1/hosts
# Expected: Valid JSON response
```

### Security Vulnerability Tests
```bash
# Test for common vulnerabilities
./scripts/security-tests.sh

# Manual security checks
# 1. SQL Injection (N/A - no database)
# 2. XSS (N/A - no web interface)  
# 3. Path Traversal
curl -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  "https://localhost:8443/api/v1/hosts/../../../etc/passwd"
# Expected: 404 or validation error

# 4. Oversized requests
curl -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  -X POST -H "Content-Type: application/json" \
  -d "$(python -c 'print("{\"service_name\":\"" + "A"*10000 + "\"}")')" \
  https://localhost:8443/api/v1/report
# Expected: Request timeout or rejection
```

## 3. Performance Testing

### Load Testing
```bash
# Built-in load test (10 concurrent requests)
# This is included in the main test suite

# Extended load test
for i in {1..100}; do
  curl -s -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
    -X POST -H "Content-Type: application/json" \
    -d "{\"service_name\":\"load-test\",\"instance_name\":\"test-$i\",\"status\":\"healthy\"}" \
    https://localhost:8443/api/v1/report &
done
wait
```

### Stress Testing with ApacheBench
```bash
# Install Apache Bench
sudo apt install apache2-utils  # Ubuntu/Debian
sudo yum install httpd-tools     # RHEL/CentOS

# Test health endpoint (no auth required)
ab -n 1000 -c 10 http://localhost:8080/health

# Test with certificates (requires Apache Bench with SSL)
# Create a test script for mTLS load testing
cat << 'EOF' > load-test-mtls.sh
#!/bin/bash
for i in {1..50}; do
  {
    time curl -s -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
      https://localhost:8443/api/v1/hosts >/dev/null
  } &
done
wait
EOF

chmod +x load-test-mtls.sh
./load-test-mtls.sh
```

### Memory and Resource Testing
```bash
# Monitor resource usage during tests
docker stats discovery-server &
STATS_PID=$!

# Run load tests
make test

# Stop monitoring
kill $STATS_PID

# Check for memory leaks
docker exec discovery-server ps aux
```

## 4. Integration Testing

### Multi-Client Testing
```bash
# Start demo environment with multiple clients
make start-demo

# Wait for clients to register
sleep 30

# Verify all clients are registered
curl -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  https://localhost:8443/api/v1/hosts | jq '.total'

# Expected: Number should be >= 4 (demo clients)
```

### Status Transition Testing
```bash
# Test status transitions: healthy -> degraded -> lost
SERVICE="integration-test"
INSTANCE="status-transitions"

# Step 1: Report healthy
curl -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  -X POST -H "Content-Type: application/json" \
  -d "{\"service_name\":\"$SERVICE\",\"instance_name\":\"$INSTANCE\",\"status\":\"healthy\"}" \
  https://localhost:8443/api/v1/report

# Verify healthy status
STATUS=$(curl -s -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  "https://localhost:8443/api/v1/hosts/$SERVICE/$INSTANCE" | jq -r '.statuses[-1].status')
echo "Current status: $STATUS"  # Should be: healthy

# Step 2: Report degraded  
curl -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  -X POST -H "Content-Type: application/json" \
  -d "{\"service_name\":\"$SERVICE\",\"instance_name\":\"$INSTANCE\",\"status\":\"degraded\"}" \
  https://localhost:8443/api/v1/report

# Verify status change
STATUS=$(curl -s -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  "https://localhost:8443/api/v1/hosts/$SERVICE/$INSTANCE" | jq -r '.statuses[-1].status')
echo "Current status: $STATUS"  # Should be: degraded

# Step 3: Wait for stale timeout (if STALE_TIMEOUT is set low)
# The status should automatically change to "lost" after timeout
```

### History Tracking Testing
```bash
# Test status history accumulation
SERVICE="history-test"
INSTANCE="hist-01"

# Send multiple status reports
for status in "healthy" "degraded" "healthy" "unhealthy" "healthy"; do
  curl -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
    -X POST -H "Content-Type: application/json" \
    -d "{\"service_name\":\"$SERVICE\",\"instance_name\":\"$INSTANCE\",\"status\":\"$status\"}" \
    https://localhost:8443/api/v1/report
  sleep 1
done

# Verify history contains all statuses
HISTORY_COUNT=$(curl -s -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  "https://localhost:8443/api/v1/hosts/$SERVICE/$INSTANCE" | jq '.statuses | length')
echo "History entries: $HISTORY_COUNT"  # Should be: 5
```

## 5. Health Metrics Testing

### Health Metrics Validation
```bash
# Test with comprehensive health metrics
curl -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  -X POST -H "Content-Type: application/json" \
  -d '{
    "service_name": "metrics-test",
    "instance_name": "metrics-01",
    "status": "healthy",
    "health_metrics": {
      "cpu_usage": 45.2,
      "memory_usage": 67.8,
      "disk_usage": 23.1,
      "network_ok": true,
      "checks": [
        {"name": "database", "status": "healthy", "value": "connected"},
        {"name": "cache", "status": "degraded", "value": "slow"}
      ],
      "overall_score": 85
    }
  }' \
  https://localhost:8443/api/v1/report

# Verify metrics are stored correctly
curl -s -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  "https://localhost:8443/api/v1/hosts/metrics-test/metrics-01" | jq '.statuses[-1].health_metrics'
```

### Stale Host Detection Testing
```bash
# Test with custom short timeout for testing
# (Requires restarting with STALE_TIMEOUT=30)

echo "Testing stale host detection..."

# Step 1: Report a host as healthy
curl -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  -X POST -H "Content-Type: application/json" \
  -d '{"service_name":"stale-test","instance_name":"stale-01","status":"healthy"}' \
  https://localhost:8443/api/v1/report

# Step 2: Verify it shows as healthy
STATUS=$(curl -s -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  https://localhost:8443/api/v1/hosts | jq -r '.hosts[] | select(.service_name=="stale-test") | .status')
echo "Initial status: $STATUS"  # Should be: healthy

# Step 3: Wait longer than stale timeout
echo "Waiting for stale timeout..."
sleep 35

# Step 4: Verify it shows as lost
STATUS=$(curl -s -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  https://localhost:8443/api/v1/hosts | jq -r '.hosts[] | select(.service_name=="stale-test") | .status')
echo "Status after timeout: $STATUS"  # Should be: lost

# Step 5: Report again and verify it returns to healthy
curl -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  -X POST -H "Content-Type: application/json" \
  -d '{"service_name":"stale-test","instance_name":"stale-01","status":"healthy"}' \
  https://localhost:8443/api/v1/report

STATUS=$(curl -s -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  https://localhost:8443/api/v1/hosts | jq -r '.hosts[] | select(.service_name=="stale-test") | .status')
echo "Status after recovery: $STATUS"  # Should be: healthy
```

## 6. API Endpoint Testing

### Complete API Test Suite
```bash
# Create comprehensive API test script
cat << 'EOF' > api-test-suite.sh
#!/bin/bash

BASE_URL="https://localhost:8443"
HEALTH_URL="http://localhost:8080"
CERT="--cert ca/certs/test-client.crt --key ca/certs/test-client.key"

echo "=== API Endpoint Testing ==="

# Test 1: Health endpoint (no auth)
echo "Testing health endpoint..."
RESPONSE=$(curl -s -w "%{http_code}" $HEALTH_URL/health)
HTTP_CODE="${RESPONSE: -3}"
if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ Health endpoint accessible"
else
    echo "✗ Health endpoint failed (HTTP $HTTP_CODE)"
fi

# Test 2: POST /api/v1/report
echo "Testing status report endpoint..."
RESPONSE=$(curl -s -k $CERT -w "%{http_code}" \
    -X POST -H "Content-Type: application/json" \
    -d '{"service_name":"api-test","instance_name":"test-01","status":"healthy"}' \
    $BASE_URL/api/v1/report)
HTTP_CODE="${RESPONSE: -3}"
if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ Status report successful"
else
    echo "✗ Status report failed (HTTP $HTTP_CODE)"
fi

# Test 3: GET /api/v1/hosts
echo "Testing host discovery endpoint..."
RESPONSE=$(curl -s -k $CERT -w "%{http_code}" $BASE_URL/api/v1/hosts)
HTTP_CODE="${RESPONSE: -3}"
if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ Host discovery successful"
else
    echo "✗ Host discovery failed (HTTP $HTTP_CODE)"
fi

# Test 4: GET /api/v1/hosts/{service}/{instance}
echo "Testing specific host endpoint..."
RESPONSE=$(curl -s -k $CERT -w "%{http_code}" $BASE_URL/api/v1/hosts/api-test/test-01)
HTTP_CODE="${RESPONSE: -3}"
if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ Specific host query successful"
else
    echo "✗ Specific host query failed (HTTP $HTTP_CODE)"
fi

# Test 5: Invalid endpoint
echo "Testing 404 handling..."
RESPONSE=$(curl -s -k $CERT -w "%{http_code}" $BASE_URL/api/v1/nonexistent)
HTTP_CODE="${RESPONSE: -3}"
if [ "$HTTP_CODE" = "404" ]; then
    echo "✓ 404 handling correct"
else
    echo "✗ 404 handling incorrect (HTTP $HTTP_CODE)"
fi

echo "=== API Testing Complete ==="
EOF

chmod +x api-test-suite.sh
./api-test-suite.sh
```

## 7. Error Handling Testing

### Invalid Data Testing
```bash
# Test various invalid payloads
echo "Testing error handling..."

# Missing required fields
curl -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  -X POST -H "Content-Type: application/json" \
  -d '{"service_name":"test"}' \
  https://localhost:8443/api/v1/report
# Expected: HTTP 400

# Invalid JSON
curl -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  -X POST -H "Content-Type: application/json" \
  -d '{invalid json}' \
  https://localhost:8443/api/v1/report
# Expected: HTTP 400

# Wrong HTTP method
curl -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  -X DELETE https://localhost:8443/api/v1/report
# Expected: HTTP 405 Method Not Allowed
```

## 8. Production Testing

### Pre-Production Validation
```bash
# Run full test suite in production environment
./scripts/test-discovery.sh --production

# Performance baseline testing
./scripts/performance-test.sh --baseline

# Certificate validation
./scripts/validate-certificates.sh --production

# Security scan
./scripts/security-scan.sh --production
```

### Smoke Tests for Deployed Environment
```bash
# Create smoke test script for production
cat << 'EOF' > smoke-test.sh
#!/bin/bash

DISCOVERY_URL="${1:-https://discovery.company.com:8443}"
HEALTH_URL="${2:-http://discovery.company.com:8080}"

echo "Running smoke tests against $DISCOVERY_URL"

# Test 1: Health check
if curl -f -s "$HEALTH_URL/health" >/dev/null; then
    echo "✓ Health check passed"
else
    echo "✗ Health check failed"
    exit 1
fi

# Test 2: API accessibility (with production certificates)
if curl -f -s --cert /etc/ssl/certs/client.crt --key /etc/ssl/certs/client.key \
    "$DISCOVERY_URL/api/v1/hosts" >/dev/null; then
    echo "✓ API accessible"
else
    echo "✗ API not accessible"
    exit 1
fi

# Test 3: Service registration
HOST_COUNT=$(curl -s --cert /etc/ssl/certs/client.crt --key /etc/ssl/certs/client.key \
    "$DISCOVERY_URL/api/v1/hosts" | jq -r '.total')

if [ "$HOST_COUNT" -gt 0 ]; then
    echo "✓ Hosts registered ($HOST_COUNT total)"
else
    echo "⚠ No hosts registered"
fi

echo "Smoke tests completed successfully"
EOF

chmod +x smoke-test.sh
```

## 9. Continuous Integration Testing

### CI/CD Pipeline Tests
```bash
# Create CI test script
cat << 'EOF' > ci-test.sh
#!/bin/bash
set -e

echo "=== CI/CD Testing Pipeline ==="

# Step 1: Build images
echo "Building Docker images..."
make build-all

# Step 2: Initialize system
echo "Initializing system..."
make init

# Step 3: Run automated tests
echo "Running test suite..."
make test

# Step 4: Security tests
echo "Running security tests..."
./scripts/security-tests.sh

# Step 5: Performance tests
echo "Running performance tests..."
./scripts/performance-test.sh --ci

# Step 6: Cleanup
echo "Cleaning up..."
make clean

echo "=== CI/CD Pipeline Complete ==="
EOF

chmod +x ci-test.sh
```

### GitHub Actions Example
```yaml
# .github/workflows/test.yml
name: Test Suite

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Install dependencies
      run: |
        sudo apt-get update
        sudo apt-get install -y jq curl
    
    - name: Run test suite
      run: |
        cd management
        chmod +x scripts/*.sh
        ./ci-test.sh
```

## 10. Manual Testing Procedures

### Interactive Testing Checklist

**System Initialization**
- [ ] `make init` completes without errors
- [ ] All certificates are generated in `ca/certs/`
- [ ] Services start successfully (`make status` shows running containers)
- [ ] Health check returns OK (`make health`)

**Basic Functionality**
- [ ] Test client can register successfully
- [ ] Host appears in discovery list
- [ ] Status updates are reflected immediately
- [ ] History tracking works (multiple status reports)

**Security Validation**
- [ ] Requests without certificates are rejected
- [ ] Invalid certificates are rejected
- [ ] Valid certificates are accepted
- [ ] Certificate chain validation works

**Error Conditions**
- [ ] Invalid JSON is rejected with 400 error
- [ ] Missing required fields return 400 error
- [ ] Non-existent endpoints return 404 error
- [ ] Wrong HTTP methods return 405 error

**Performance and Limits**
- [ ] System handles concurrent requests
- [ ] Memory usage remains stable under load
- [ ] Response times are acceptable (<1s for normal operations)
- [ ] History limits are enforced (MAX_HISTORY setting)

**Stale Host Detection**
- [ ] Hosts show as "lost" after STALE_TIMEOUT
- [ ] Lost hosts return to reported status when they check in
- [ ] Timeout is configurable via environment variable

## 11. Test Data Management

### Generate Test Data
```bash
# Create test data generator
cat << 'EOF' > generate-test-data.sh
#!/bin/bash

SERVICES=("web-service" "api-service" "database" "cache" "worker")
STATUSES=("healthy" "degraded" "unhealthy")

echo "Generating test data..."

for service in "${SERVICES[@]}"; do
    for i in {1..3}; do
        instance="$service-0$i"
        status="${STATUSES[$RANDOM % ${#STATUSES[@]}]}"
        
        curl -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
            -X POST -H "Content-Type: application/json" \
            -d "{
                \"service_name\":\"$service\",
                \"instance_name\":\"$instance\",
                \"status\":\"$status\",
                \"health_metrics\":{
                    \"cpu_usage\":$((RANDOM % 100)),
                    \"memory_usage\":$((RANDOM % 100)),
                    \"disk_usage\":$((RANDOM % 100)),
                    \"network_ok\":true
                }
            }" \
            https://localhost:8443/api/v1/report
        
        echo "Registered $service:$instance as $status"
    done
done

echo "Test data generation complete"
EOF

chmod +x generate-test-data.sh
```

## 12. Test Environment Cleanup

### Cleanup Scripts
```bash
# Reset test environment
make clean-all

# Remove test data
rm -f api-test-suite.sh smoke-test.sh ci-test.sh generate-test-data.sh

# Reset to clean state
make init
```

## Testing Checklist

### Pre-Deployment Testing
- [ ] All automated tests pass (`make test`)
- [ ] Security tests pass
- [ ] Performance tests meet requirements
- [ ] Load tests demonstrate acceptable performance
- [ ] Error handling tests pass
- [ ] Manual testing checklist completed

### Production Testing
- [ ] Smoke tests pass in production environment
- [ ] Real client certificates work
- [ ] Monitoring and alerting function correctly
- [ ] Backup and restore procedures tested
- [ ] Disaster recovery plan validated

### Ongoing Testing
- [ ] Regular automated test execution
- [ ] Performance monitoring and alerting
- [ ] Certificate expiration monitoring
- [ ] Capacity planning based on usage patterns

---

## Troubleshooting Test Failures

### Common Test Issues

**Certificate Errors**
```bash
# Regenerate certificates
make clean-all
make init

# Verify certificate chain
openssl verify -CAfile ca/certs/ca_chain.crt ca/certs/test-client.crt
```

**Connection Refused**
```bash
# Check if services are running
make status

# Restart services
make restart

# Check logs
make logs-server
```

**Test Timeouts**
```bash
# Increase timeout values in test script
export TEST_TIMEOUT=60

# Check system resources
docker stats
```

This comprehensive testing guide ensures the Host Discovery Service is thoroughly validated before production deployment and maintains reliability in production use.