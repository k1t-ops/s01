# Test Runner Dockerfile for s01
FROM alpine:3.18

# Install runtime dependencies
# Note: awk, grep, sed are already included in busybox
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    wget \
    openssl \
    ca-certificates \
    netcat-openbsd \
    bind-tools \
    busybox-extras \
    postgresql-client \
    mysql-client \
    redis \
    httpie \
    coreutils

# Create directories
RUN mkdir -p /tests /results /tmp/test-logs

# Copy test scripts from the build context (management directory)
COPY tests/run-tests.sh /tests/
COPY tests/Makefile /tests/

# Make scripts executable
RUN chmod +x /tests/*.sh

# Set working directory
WORKDIR /tests

# Environment variables for test configuration
ENV TEST_TIMEOUT=300 \
    PARALLEL_TESTS=4 \
    VERBOSE=false \
    JUNIT_OUTPUT=/results/junit.xml \
    JSON_OUTPUT=/results/results.json \
    HTML_OUTPUT=/results/report.html \
    LOG_DIR=/tmp/test-logs

# Default command runs all tests
ENTRYPOINT ["/tests/run-tests.sh"]
CMD ["all"]
