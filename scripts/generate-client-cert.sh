#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
CA_URL="https://localhost:9000"
PROVISIONER="admin"
DEFAULT_VALIDITY="8760h" # 1 year

# Function to display usage
usage() {
    echo -e "${BLUE}Usage: $0 [OPTIONS]${NC}"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  -s, --service-name NAME     Service name (required)"
    echo "  -i, --instance-name NAME    Instance name (required)"
    echo "  -o, --output-dir DIR        Output directory for certificates (default: ./certs)"
    echo "  -h, --host HOSTNAME         Additional hostname/IP for SAN (can be used multiple times)"
    echo "  -v, --validity DURATION     Certificate validity period (default: 8760h)"
    echo "  -p, --provisioner NAME      Step-CA provisioner name (default: admin)"
    echo "  -u, --ca-url URL           Step-CA URL (default: https://localhost:9000)"
    echo "  --help                      Show this help message"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  $0 -s web-service -i web-01"
    echo "  $0 -s api-gateway -i gw-prod-1 -h api.example.com -h 192.168.1.100"
    echo "  $0 -s database -i db-primary -o /etc/ssl/database -v 4380h"
    echo ""
    echo -e "${YELLOW}Environment Variables:${NC}"
    echo "  CA_PASSWORD    - Step-CA admin password (if not set, will prompt)"
    echo "  STEP_CA_URL    - Override default CA URL"
    echo "  OUTPUT_DIR     - Default output directory"
}

# Parse command line arguments
SERVICE_NAME=""
INSTANCE_NAME=""
OUTPUT_DIR="${OUTPUT_DIR:-./certs}"
ADDITIONAL_HOSTS=()
VALIDITY="$DEFAULT_VALIDITY"

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--service-name)
            SERVICE_NAME="$2"
            shift 2
            ;;
        -i|--instance-name)
            INSTANCE_NAME="$2"
            shift 2
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--host)
            ADDITIONAL_HOSTS+=("$2")
            shift 2
            ;;
        -v|--validity)
            VALIDITY="$2"
            shift 2
            ;;
        -p|--provisioner)
            PROVISIONER="$2"
            shift 2
            ;;
        -u|--ca-url)
            CA_URL="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$SERVICE_NAME" ]]; then
    echo -e "${RED}Error: Service name is required (-s/--service-name)${NC}"
    usage
    exit 1
fi

if [[ -z "$INSTANCE_NAME" ]]; then
    echo -e "${RED}Error: Instance name is required (-i/--instance-name)${NC}"
    usage
    exit 1
fi

# Use environment variable for CA URL if set
if [[ -n "$STEP_CA_URL" ]]; then
    CA_URL="$STEP_CA_URL"
fi

# Certificate names
CERT_NAME="${SERVICE_NAME}-${INSTANCE_NAME}"
CERT_FILE="${OUTPUT_DIR}/${CERT_NAME}.crt"
KEY_FILE="${OUTPUT_DIR}/${CERT_NAME}.key"

echo -e "${GREEN}Generating client certificate for ${SERVICE_NAME}:${INSTANCE_NAME}${NC}"
echo -e "${YELLOW}Configuration:${NC}"
echo "  Service Name: $SERVICE_NAME"
echo "  Instance Name: $INSTANCE_NAME"
echo "  Certificate Name: $CERT_NAME"
echo "  Output Directory: $OUTPUT_DIR"
echo "  CA URL: $CA_URL"
echo "  Provisioner: $PROVISIONER"
echo "  Validity: $VALIDITY"
if [[ ${#ADDITIONAL_HOSTS[@]} -gt 0 ]]; then
    echo "  Additional Hosts: ${ADDITIONAL_HOSTS[*]}"
fi
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Check if step CLI is available
if ! command -v step &> /dev/null; then
    echo -e "${RED}Error: step CLI is not installed or not in PATH${NC}"
    echo -e "${YELLOW}Please install step CLI: https://smallstep.com/docs/step-cli/installation${NC}"
    exit 1
fi

# Check if we're using docker-compose setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"

if [[ -f "$COMPOSE_FILE" ]] && docker-compose -f "$COMPOSE_FILE" ps step-ca | grep -q "Up"; then
    echo -e "${YELLOW}Using docker-compose step-ca instance${NC}"

    # Build SAN list
    SAN_ARGS=""
    for host in "${ADDITIONAL_HOSTS[@]}"; do
        SAN_ARGS="$SAN_ARGS --san $host"
    done

    # Generate certificate using docker-compose
    if [[ -n "$CA_PASSWORD" ]]; then
        # Use provided password
        echo "$CA_PASSWORD" | docker-compose -f "$COMPOSE_FILE" exec -T step-ca step ca certificate \
            "$CERT_NAME" \
            "/tmp/${CERT_NAME}.crt" \
            "/tmp/${CERT_NAME}.key" \
            --provisioner "$PROVISIONER" \
            --provisioner-password-file /dev/stdin \
            --san "$SERVICE_NAME" \
            --san "$INSTANCE_NAME" \
            --san "$CERT_NAME" \
            $SAN_ARGS \
            --not-after "$VALIDITY"
    else
        # Prompt for password
        docker-compose -f "$COMPOSE_FILE" exec step-ca step ca certificate \
            "$CERT_NAME" \
            "/tmp/${CERT_NAME}.crt" \
            "/tmp/${CERT_NAME}.key" \
            --provisioner "$PROVISIONER" \
            --san "$SERVICE_NAME" \
            --san "$INSTANCE_NAME" \
            --san "$CERT_NAME" \
            $SAN_ARGS \
            --not-after "$VALIDITY"
    fi

    # Copy certificates from container
    docker-compose -f "$COMPOSE_FILE" cp "step-ca:/tmp/${CERT_NAME}.crt" "$CERT_FILE"
    docker-compose -f "$COMPOSE_FILE" cp "step-ca:/tmp/${CERT_NAME}.key" "$KEY_FILE"

    # Copy root CA certificate if it doesn't exist
    ROOT_CA_FILE="${OUTPUT_DIR}/root_ca.crt"
    if [[ ! -f "$ROOT_CA_FILE" ]]; then
        docker-compose -f "$COMPOSE_FILE" cp "step-ca:/home/step/certs/root_ca.crt" "$ROOT_CA_FILE"
    fi

else
    # Use local step CLI
    echo -e "${YELLOW}Using local step CLI${NC}"

    # Bootstrap step CLI if needed
    if [[ ! -f "$HOME/.step/config/defaults.json" ]]; then
        echo -e "${YELLOW}Bootstrapping step CLI...${NC}"
        step ca bootstrap --ca-url "$CA_URL"
    fi

    # Build SAN list
    SAN_ARGS=""
    for host in "${ADDITIONAL_HOSTS[@]}"; do
        SAN_ARGS="$SAN_ARGS --san $host"
    done

    # Generate certificate
    step ca certificate \
        "$CERT_NAME" \
        "$CERT_FILE" \
        "$KEY_FILE" \
        --provisioner "$PROVISIONER" \
        --san "$SERVICE_NAME" \
        --san "$INSTANCE_NAME" \
        --san "$CERT_NAME" \
        $SAN_ARGS \
        --not-after "$VALIDITY"

    # Copy root CA certificate if it doesn't exist
    ROOT_CA_FILE="${OUTPUT_DIR}/root_ca.crt"
    if [[ ! -f "$ROOT_CA_FILE" ]]; then
        step ca root "$ROOT_CA_FILE"
    fi
fi

# Set proper permissions
chmod 644 "$CERT_FILE"
chmod 600 "$KEY_FILE"
if [[ -f "${OUTPUT_DIR}/root_ca.crt" ]]; then
    chmod 644 "${OUTPUT_DIR}/root_ca.crt"
fi

echo -e "${GREEN}Certificate generated successfully!${NC}"
echo -e "${YELLOW}Files created:${NC}"
echo "  Certificate: $CERT_FILE"
echo "  Private Key: $KEY_FILE"
echo "  Root CA: ${OUTPUT_DIR}/root_ca.crt"
echo ""

# Display certificate information
echo -e "${YELLOW}Certificate Details:${NC}"
step certificate inspect "$CERT_FILE" --short

echo ""
echo -e "${GREEN}Next steps:${NC}"
echo -e "1. Copy certificates to your host:"
echo -e "   ${BLUE}scp $CERT_FILE $KEY_FILE ${OUTPUT_DIR}/root_ca.crt user@your-host:/etc/ssl/certs/${NC}"
echo ""
echo -e "2. Configure your s01 client:"
echo -e "   ${BLUE}export SERVICE_NAME='$SERVICE_NAME'${NC}"
echo -e "   ${BLUE}export INSTANCE_NAME='$INSTANCE_NAME'${NC}"
echo -e "   ${BLUE}export CERT_FILE='/etc/ssl/certs/${CERT_NAME}.crt'${NC}"
echo -e "   ${BLUE}export KEY_FILE='/etc/ssl/certs/${CERT_NAME}.key'${NC}"
echo -e "   ${BLUE}export CA_CERT_FILE='/etc/ssl/certs/root_ca.crt'${NC}"
echo ""
echo -e "3. Start the s01 client on your host"

# Create a simple environment file
ENV_FILE="${OUTPUT_DIR}/${CERT_NAME}.env"
cat > "$ENV_FILE" << EOF
# S01 Client Configuration for ${SERVICE_NAME}:${INSTANCE_NAME}
# Generated on $(date)

SERVICE_NAME=$SERVICE_NAME
INSTANCE_NAME=$INSTANCE_NAME
SERVER_URL=https://s01-server:8443
CERT_FILE=/etc/ssl/certs/${CERT_NAME}.crt
KEY_FILE=/etc/ssl/certs/${CERT_NAME}.key
CA_CERT_FILE=/etc/ssl/certs/root_ca.crt
LOG_LEVEL=info
REPORT_INTERVAL=30
EOF

echo -e "4. Environment file created: ${YELLOW}$ENV_FILE${NC}"
echo -e "   Source this file or use it with docker run --env-file"
