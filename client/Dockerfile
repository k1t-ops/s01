# Build stage
FROM golang:1.21-alpine AS builder

# Build arguments
ARG VERSION=dev
ARG BUILD_DATE
ARG GIT_COMMIT

# Install build dependencies
RUN apk add --no-cache git ca-certificates tzdata

# Create non-root user for runtime
RUN addgroup -g 1001 -S s01 && \
    adduser -u 1001 -S s01 -G s01

# Set working directory
WORKDIR /build

# Copy go mod file
COPY go.mod ./

# Download dependencies (none for this project, but good practice)
RUN go mod download

# Copy source code
COPY . .

# Build the binary with version information
RUN CGO_ENABLED=0 GOOS=linux go build \
    -a -installsuffix cgo \
    -ldflags="-w -s \
    -X main.version=${VERSION} \
    -X main.buildDate=${BUILD_DATE} \
    -X main.gitCommit=${GIT_COMMIT}" \
    -o s01-client .

# Create minimal runtime image
FROM scratch

# Copy timezone data for proper timestamp handling
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

# Copy CA certificates for HTTPS
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy user and group files
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group /etc/group

# Copy the binary from builder stage
COPY --from=builder /build/s01-client /app/s01-client

# Set working directory
WORKDIR /app

# Switch to non-root user
USER s01:s01

# Default environment variables for configuration
ENV SERVICE_NAME=docker-client \
    INSTANCE_NAME=client-01 \
    SERVER_URL=https://s01-server:8443 \
    LOG_LEVEL=info \
    REPORT_INTERVAL=30 \
    TIMEOUT=30 \
    RETRY_ATTEMPTS=3 \
    RETRY_DELAY=5

# Certificate paths (must be mounted as volumes)
ENV CERT_FILE=/etc/ssl/certs/client.crt \
    KEY_FILE=/etc/ssl/certs/client.key \
    CA_CERT_FILE=/etc/ssl/certs/ca.crt

# Health monitoring configuration
ENV HEALTH_CPU_THRESHOLD=80.0 \
    HEALTH_MEMORY_THRESHOLD=85.0 \
    HEALTH_DISK_THRESHOLD=85.0 \
    HEALTH_NETWORK_ENABLED=true \
    HEALTH_SCORE_HEALTHY_MIN=80 \
    HEALTH_SCORE_DEGRADED_MIN=60

# Metadata labels
LABEL org.opencontainers.image.title="s01 Client" \
      org.opencontainers.image.description="Service discovery client with health monitoring" \
      org.opencontainers.image.vendor="s01" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${GIT_COMMIT}"

# Run the client
ENTRYPOINT ["/app/s01-client"]
