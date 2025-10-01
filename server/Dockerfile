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
    -o s01-server .

# Create minimal runtime image with curl for healthcheck support
FROM alpine:3.18

# Install curl for healthcheck
RUN apk add --no-cache ca-certificates curl tzdata

# Copy user and group files
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group /etc/group

WORKDIR /app

# Copy binary and zoneinfo
COPY --from=builder /build/s01-server /app/s01-server
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

# Certificates
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

USER s01:s01

ENV SERVER_PORT=8443 \
    HEALTH_PORT=8080 \
    MAX_HISTORY=100 \
    STALE_TIMEOUT=300 \
    LOG_LEVEL=info

ENV CERT_FILE=/etc/ssl/certs/server.crt \
    KEY_FILE=/etc/ssl/certs/server.key \
    CA_CERT_FILE=/etc/ssl/certs/ca.crt

LABEL org.opencontainers.image.title="s01 Server" \
      org.opencontainers.image.description="Service discovery server with mTLS authentication" \
      org.opencontainers.image.vendor="s01" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${GIT_COMMIT}"

EXPOSE 8443 8080
ENTRYPOINT ["/app/s01-server"]
