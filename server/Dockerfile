# Build stage
FROM golang:1.21-alpine AS builder

# Install git and ca-certificates for fetching dependencies
RUN apk add --no-cache git ca-certificates

# Set working directory
WORKDIR /app

# Copy go mod file (go.sum not needed since no external dependencies)
COPY go.mod ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o discovery-server .

# Runtime stage
FROM alpine:latest

# Install ca-certificates for HTTPS
RUN apk --no-cache add ca-certificates curl

# Create non-root user
RUN addgroup -g 1001 -S discovery && \
    adduser -u 1001 -S discovery -G discovery

# Set working directory
WORKDIR /app

# Copy the binary from builder stage
COPY --from=builder /app/discovery-server .

# Create directories for certificates and config
RUN mkdir -p /etc/ssl/certs /etc/discovery && \
    chown -R discovery:discovery /app /etc/ssl/certs /etc/discovery

# Switch to non-root user
USER discovery

# Expose the HTTPS port
EXPOSE 8443

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -k https://localhost:8443/health || exit 1

# Run the binary
CMD ["./discovery-server"]
