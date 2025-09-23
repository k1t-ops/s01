# Build stage
FROM golang:1.21-alpine AS builder

# Install ca-certificates for HTTPS
RUN apk add --no-cache ca-certificates git

# Set working directory
WORKDIR /app

# Copy go mod file (go.sum not needed since no external dependencies)
COPY go.mod ./

# Download dependencies (there are none, but good practice)
RUN go mod download

# Copy source code
COPY . .

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o s01-client .

# Runtime stage
FROM alpine:latest

# Install ca-certificates and curl for health checks
RUN apk --no-cache add ca-certificates curl

# Create non-root user
RUN addgroup -g 1001 -S s01 && \
    adduser -u 1001 -S s01 -G s01

# Set working directory
WORKDIR /app

# Copy the binary from builder stage
COPY --from=builder /app/s01-client .

# Create directories for certificates and config
RUN mkdir -p /etc/ssl/certs /etc/s01 && \
    chown -R s01:s01 /app /etc/ssl/certs /etc/s01

# Health configuration can be provided via environment variables or mounted config

# Switch to non-root user
USER s01

# Default environment variables
ENV SERVICE_NAME=docker-client
ENV INSTANCE_NAME=client-01
ENV SERVER_URL=https://s01-server:8443
ENV CERT_FILE=/etc/ssl/certs/client.crt
ENV KEY_FILE=/etc/ssl/certs/client.key
ENV CA_CERT_FILE=/etc/ssl/certs/root_ca.crt
ENV LOG_LEVEL=info
ENV REPORT_INTERVAL=30
ENV TIMEOUT=30
ENV RETRY_ATTEMPTS=3
ENV RETRY_DELAY=5

# Health check environment variables
ENV HEALTH_CPU_THRESHOLD=80.0
ENV HEALTH_MEMORY_THRESHOLD=85.0
ENV HEALTH_DISK_THRESHOLD=85.0
ENV HEALTH_NETWORK_ENABLED=true
ENV HEALTH_SCORE_HEALTHY_MIN=80
ENV HEALTH_SCORE_DEGRADED_MIN=60

# Health check - verify the client can start (not that it can connect, since that requires certs)
HEALTHCHECK --interval=60s --timeout=10s --start-period=10s --retries=3 \
    CMD /app/s01-client --help >/dev/null 2>&1 || exit 1

# Run the client
CMD ["./s01-client"]
