#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CA_NAME="Host S01 CA"
CA_PASSWORD="${CA_PASSWORD:-changeme123}"
CA_URL="https://localhost:9000"
SERVER_NAME="s01-server"
SERVER_DNS="localhost,s01-server,127.0.0.1"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CA_DIR="$PROJECT_DIR/ca"
STEP_DIR="$CA_DIR/step"
CERTS_DIR="$CA_DIR/certs"
CONFIG_DIR="$CA_DIR/config"

echo -e "${GREEN}Initializing Host S01 CA...${NC}"

# Create directories
mkdir -p "$STEP_DIR/secrets" "$CERTS_DIR" "$CONFIG_DIR"

# Create CA password file
echo "$CA_PASSWORD" > "$STEP_DIR/secrets/password"
chmod 600 "$STEP_DIR/secrets/password"

# Check if CA is already initialized
if [ ! -f "$STEP_DIR/config/ca.json" ]; then
    echo -e "${YELLOW}CA not found, initializing...${NC}"

    # Start step-ca init container
    echo -e "${YELLOW}Starting step-ca initialization container...${NC}"
    docker-compose -f "$PROJECT_DIR/docker-compose.yml" --profile init up step-ca-init

    if [ ! -f "$STEP_DIR/config/ca.json" ]; then
        echo -e "${RED}Failed to initialize step-ca${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}CA already initialized${NC}"
fi

# Start step-ca service
echo -e "${YELLOW}Starting step-ca service...${NC}"
docker-compose -f "$PROJECT_DIR/docker-compose.yml" up -d step-ca

# Wait for step-ca to be ready
echo -e "${YELLOW}Waiting for step-ca to be ready...${NC}"
timeout=60
count=0
while [ $count -lt $timeout ]; do
    if docker-compose -f "$PROJECT_DIR/docker-compose.yml" exec step-ca step ca health > /dev/null 2>&1; then
        echo -e "${GREEN}Step-ca is ready${NC}"
        break
    fi
    sleep 2
    count=$((count + 2))
done

if [ $count -ge $timeout ]; then
    echo -e "${RED}Step-ca failed to start within $timeout seconds${NC}"
    exit 1
fi

# Skip bootstrap and provisioner setup for demo - not required for basic functionality
echo -e "${YELLOW}Skipping step CLI bootstrap (not required for demo)...${NC}"

# Generate server certificate for s01 service
echo -e "${YELLOW}Generating server certificate...${NC}"
docker-compose -f "$PROJECT_DIR/docker-compose.yml" exec -T step-ca step ca certificate \
    "$SERVER_NAME" \
    "/tmp/server.crt" \
    "/tmp/server.key" \
    --provisioner admin \
    --provisioner-password-file /home/step/secrets/password \
    --san "$SERVER_DNS" \
    --not-after 24h || echo "Server certificate may already exist"

# Copy server certificate to host
docker-compose -f "$PROJECT_DIR/docker-compose.yml" cp step-ca:/tmp/server.crt "$CERTS_DIR/"
docker-compose -f "$PROJECT_DIR/docker-compose.yml" cp step-ca:/tmp/server.key "$CERTS_DIR/"

# Copy root CA certificate
docker-compose -f "$PROJECT_DIR/docker-compose.yml" cp step-ca:/home/step/certs/root_ca.crt "$CERTS_DIR/"

# Copy intermediate CA certificate
docker-compose -f "$PROJECT_DIR/docker-compose.yml" cp step-ca:/home/step/certs/intermediate_ca.crt "$CERTS_DIR/"

# Create certificate chain for server (intermediate + root)
cat "$CERTS_DIR/intermediate_ca.crt" "$CERTS_DIR/root_ca.crt" > "$CERTS_DIR/ca_chain.crt"

# Set proper permissions
chmod 644 "$CERTS_DIR/server.crt" "$CERTS_DIR/root_ca.crt" "$CERTS_DIR/intermediate_ca.crt" "$CERTS_DIR/ca_chain.crt"
chmod 600 "$CERTS_DIR/server.key"

# Create example client certificate for testing
echo -e "${YELLOW}Creating example client certificate for testing...${NC}"
docker-compose -f "$PROJECT_DIR/docker-compose.yml" exec -T step-ca step ca certificate \
    "test-host" \
    "/tmp/test-client.crt" \
    "/tmp/test-client.key" \
    --provisioner admin \
    --provisioner-password-file /home/step/secrets/password \
    --san "test-host" \
    --not-after 24h || echo "Test client certificate may already exist"

# Copy test client certificate to host
docker-compose -f "$PROJECT_DIR/docker-compose.yml" cp step-ca:/tmp/test-client.crt "$CERTS_DIR/"
docker-compose -f "$PROJECT_DIR/docker-compose.yml" cp step-ca:/tmp/test-client.key "$CERTS_DIR/"
chmod 644 "$CERTS_DIR/test-client.crt"
chmod 600 "$CERTS_DIR/test-client.key"

# Generate certificates for docker client services
echo -e "${YELLOW}Creating certificates for docker client services...${NC}"

# Client certificates for docker services
CLIENT_SERVICES=(
    "web-service:web-01"
    "api-service:api-01"
    "database:db-primary"
    "worker-service:worker-01"
)

for service_instance in "${CLIENT_SERVICES[@]}"; do
    SERVICE_NAME="${service_instance%:*}"
    INSTANCE_NAME="${service_instance#*:}"
    CERT_NAME="${SERVICE_NAME}-${INSTANCE_NAME}"

    echo -e "${YELLOW}Generating certificate for ${SERVICE_NAME}:${INSTANCE_NAME}...${NC}"

    docker-compose -f "$PROJECT_DIR/docker-compose.yml" exec -T step-ca step ca certificate \
        "$CERT_NAME" \
        "/tmp/${CERT_NAME}.crt" \
        "/tmp/${CERT_NAME}.key" \
        --provisioner admin \
        --provisioner-password-file /home/step/secrets/password \
        --san "$SERVICE_NAME" \
        --san "$INSTANCE_NAME" \
        --san "$CERT_NAME" \
        --not-after 24h || echo "Certificate for $CERT_NAME may already exist"

    # Copy certificate to host (using generic client.crt name for docker volume mount)
    docker-compose -f "$PROJECT_DIR/docker-compose.yml" cp "step-ca:/tmp/${CERT_NAME}.crt" "$CERTS_DIR/client.crt"
    docker-compose -f "$PROJECT_DIR/docker-compose.yml" cp "step-ca:/tmp/${CERT_NAME}.key" "$CERTS_DIR/client.key"

    # Also keep individual named certificates for reference
    docker-compose -f "$PROJECT_DIR/docker-compose.yml" cp "step-ca:/tmp/${CERT_NAME}.crt" "$CERTS_DIR/${CERT_NAME}.crt"
    docker-compose -f "$PROJECT_DIR/docker-compose.yml" cp "step-ca:/tmp/${CERT_NAME}.key" "$CERTS_DIR/${CERT_NAME}.key"

    chmod 644 "$CERTS_DIR/${CERT_NAME}.crt" "$CERTS_DIR/client.crt"
    chmod 600 "$CERTS_DIR/${CERT_NAME}.key" "$CERTS_DIR/client.key"
done

echo -e "${GREEN}CA initialization complete!${NC}"
echo -e "${GREEN}Files created:${NC}"
echo -e "  ${YELLOW}Root CA:${NC} $CERTS_DIR/root_ca.crt"
echo -e "  ${YELLOW}Server cert:${NC} $CERTS_DIR/server.crt"
echo -e "  ${YELLOW}Server key:${NC} $CERTS_DIR/server.key"
echo -e "  ${YELLOW}Test client cert:${NC} $CERTS_DIR/test-client.crt"
echo -e "  ${YELLOW}Test client key:${NC} $CERTS_DIR/test-client.key"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo -e "1. Build and start the s01 server: ${YELLOW}docker-compose up -d s01-server${NC}"
echo -e "2. Start test client: ${YELLOW}docker-compose --profile test up -d test-client${NC}"
echo -e "3. Start demo clients: ${YELLOW}docker-compose --profile demo up -d${NC}"
echo -e "4. Test with: ${YELLOW}./scripts/test-s01.sh${NC}"
echo -e "5. Monitor health: ${YELLOW}make health-monitor${NC}"
echo -e "6. Generate client certificates for your hosts using the step CLI"
echo ""
echo -e "${GREEN}CA Web UI:${NC} $CA_URL"
echo -e "${GREEN}CA Admin Password:${NC} $CA_PASSWORD"
