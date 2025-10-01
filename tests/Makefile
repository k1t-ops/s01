# Test Suite Makefile
# This Makefile is used within the test runner container

.PHONY: all connectivity api discovery performance clean help

# Default target
all: connectivity api discovery performance

# Run connectivity tests
connectivity:
	@echo "Running connectivity tests..."
	@/tests/run-tests.sh connectivity

# Run API tests
api:
	@echo "Running API tests..."
	@/tests/run-tests.sh api

# Run service discovery tests
discovery:
	@echo "Running service discovery tests..."
	@/tests/run-tests.sh discovery

# Run performance tests
performance:
	@echo "Running performance tests..."
	@/tests/run-tests.sh performance

# Clean test results
clean:
	@echo "Cleaning test results..."
	@rm -rf /results/*
	@rm -rf /tmp/test-logs/*

# Show help
help:
	@echo "Available test targets:"
	@echo "  make all          - Run all test suites"
	@echo "  make connectivity - Run connectivity tests"
	@echo "  make api          - Run API tests"
	@echo "  make discovery    - Run service discovery tests"
	@echo "  make performance  - Run performance tests"
	@echo "  make clean        - Clean test results"
	@echo "  make help         - Show this help message"
