#!/bin/bash
set -euo pipefail

# Test Certificate Generation Script
# This script generates self-signed certificates for the test environment

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CERTS_DIR="${BASE_DIR}/ca/certs"
CA_DIR="${BASE_DIR}/ca"
STEP_DIR="${CA_DIR}/step"
CONFIG_DIR="${CA_DIR}/config"

# Certificate settings
CERT_VALIDITY_DAYS=365
CA_VALIDITY_DAYS=3650
COUNTRY="US"
STATE="State"
CITY="City"
ORG="s01-test"
OU="Testing"

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Create directory structure
create_directories() {
    log_info "Creating certificate directories..."
    mkdir -p "$CERTS_DIR"
    mkdir -p "$STEP_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$CA_DIR/secrets"
    log_info "✓ Directories created"
}

# Generate CA certificate
generate_ca() {
    log_info "Generating CA certificate..."

    if [[ -f "$CERTS_DIR/root_ca.crt" ]] && [[ -f "$CERTS_DIR/root_ca.key" ]]; then
        log_warn "CA certificate already exists, skipping generation"
        return 0
    fi

    # Generate CA private key
    openssl genrsa -out "$CERTS_DIR/root_ca.key" 4096 2>/dev/null

    # Generate CA certificate
    openssl req -new -x509 -sha256 -days "$CA_VALIDITY_DAYS" \
        -key "$CERTS_DIR/root_ca.key" \
        -out "$CERTS_DIR/root_ca.crt" \
        -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=$OU/CN=s01-test-ca" 2>/dev/null

    # Also create a copy named ca.crt for compatibility
    cp "$CERTS_DIR/root_ca.crt" "$CERTS_DIR/ca.crt"
    cp "$CERTS_DIR/root_ca.key" "$CERTS_DIR/ca.key"

    # Set permissions
    chmod 600 "$CERTS_DIR/root_ca.key" "$CERTS_DIR/ca.key"
    chmod 644 "$CERTS_DIR/root_ca.crt" "$CERTS_DIR/ca.crt"

    log_info "✓ CA certificate generated"
}

# Generate server certificate
generate_server_cert() {
    log_info "Generating server certificate..."

    if [[ -f "$CERTS_DIR/server.crt" ]] && [[ -f "$CERTS_DIR/server.key" ]]; then
        log_warn "Server certificate already exists, skipping generation"
        return 0
    fi

    # Create server certificate config
    cat > "$CERTS_DIR/server.conf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = $COUNTRY
ST = $STATE
L = $CITY
O = $ORG
OU = Server
CN = s01-server

[v3_req]
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = s01-server
DNS.3 = s01-server-test
DNS.4 = *.s01.local
IP.1 = 127.0.0.1
IP.2 = 172.21.0.10
EOF

    # Generate server private key
    openssl genrsa -out "$CERTS_DIR/server.key" 2048 2>/dev/null

    # Generate server CSR
    openssl req -new -key "$CERTS_DIR/server.key" \
        -out "$CERTS_DIR/server.csr" \
        -config "$CERTS_DIR/server.conf" 2>/dev/null

    # Sign server certificate
    openssl x509 -req -in "$CERTS_DIR/server.csr" \
        -CA "$CERTS_DIR/root_ca.crt" \
        -CAkey "$CERTS_DIR/root_ca.key" \
        -CAcreateserial \
        -out "$CERTS_DIR/server.crt" \
        -days "$CERT_VALIDITY_DAYS" \
        -sha256 \
        -extensions v3_req \
        -extfile "$CERTS_DIR/server.conf" 2>/dev/null

    # Set permissions
    chmod 600 "$CERTS_DIR/server.key"
    chmod 644 "$CERTS_DIR/server.crt"

    # Clean up CSR
    rm -f "$CERTS_DIR/server.csr"

    log_info "✓ Server certificate generated"
}

# Generate client certificate
generate_client_cert() {
    local name="${1:-client}"
    local cn="${2:-$name}"

    log_info "Generating certificate for: $name (CN=$cn)"

    if [[ -f "$CERTS_DIR/${name}.crt" ]] && [[ -f "$CERTS_DIR/${name}.key" ]]; then
        log_warn "Certificate for $name already exists, skipping"
        return 0
    fi

    # Create client certificate config
    cat > "$CERTS_DIR/${name}.conf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = $COUNTRY
ST = $STATE
L = $CITY
O = $ORG
OU = Client
CN = $cn

[v3_req]
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOF

    # Generate client private key
    openssl genrsa -out "$CERTS_DIR/${name}.key" 2048 2>/dev/null

    # Generate client CSR
    openssl req -new -key "$CERTS_DIR/${name}.key" \
        -out "$CERTS_DIR/${name}.csr" \
        -config "$CERTS_DIR/${name}.conf" 2>/dev/null

    # Sign client certificate
    openssl x509 -req -in "$CERTS_DIR/${name}.csr" \
        -CA "$CERTS_DIR/root_ca.crt" \
        -CAkey "$CERTS_DIR/root_ca.key" \
        -CAcreateserial \
        -out "$CERTS_DIR/${name}.crt" \
        -days "$CERT_VALIDITY_DAYS" \
        -sha256 \
        -extensions v3_req \
        -extfile "$CERTS_DIR/${name}.conf" 2>/dev/null

    # Set permissions
    chmod 600 "$CERTS_DIR/${name}.key"
    chmod 644 "$CERTS_DIR/${name}.crt"

    # Clean up CSR and conf
    rm -f "$CERTS_DIR/${name}.csr"
    rm -f "$CERTS_DIR/${name}.conf"

    log_info "✓ Certificate for $name generated"
}

# Create step-ca password file for testing
create_step_password() {
    log_info "Creating step-ca password file..."

    mkdir -p "$STEP_DIR/secrets"
    echo "testpassword123" > "$STEP_DIR/secrets/password"
    chmod 600 "$STEP_DIR/secrets/password"

    log_info "✓ Password file created"
}

# Create step-ca config (optional, for step-ca compatibility)
create_step_config() {
    log_info "Creating step-ca configuration..."

    mkdir -p "$STEP_DIR/config"

    # Create a basic ca.json for step-ca (if using step-ca in tests)
    cat > "$STEP_DIR/config/ca.json" << 'EOF'
{
    "root": "/etc/ssl/step/certs/root_ca.crt",
    "crt": "/etc/ssl/step/certs/intermediate_ca.crt",
    "key": "/etc/ssl/step/secrets/intermediate_ca_key",
    "address": ":9000",
    "dnsNames": ["localhost", "step-ca", "s01-ca-test"],
    "authority": {
        "provisioners": [
            {
                "type": "JWK",
                "name": "admin",
                "key": {
                    "use": "sig",
                    "kty": "EC",
                    "kid": "test",
                    "crv": "P-256",
                    "alg": "ES256"
                },
                "encryptedKey": "test"
            }
        ]
    },
    "tls": {
        "cipherSuites": [
            "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
            "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
        ],
        "minVersion": 1.2,
        "maxVersion": 1.3,
        "renegotiation": false
    }
}
EOF

    log_info "✓ Step-ca configuration created"
}

# Create certificate chain file
create_cert_chain() {
    log_info "Creating certificate chain..."

    # Create ca_chain.crt (same as root for self-signed)
    cp "$CERTS_DIR/root_ca.crt" "$CERTS_DIR/ca_chain.crt"

    log_info "✓ Certificate chain created"
}

# Verify certificates
verify_certificates() {
    log_info "Verifying certificates..."

    # Verify server certificate
    if openssl verify -CAfile "$CERTS_DIR/root_ca.crt" "$CERTS_DIR/server.crt" > /dev/null 2>&1; then
        log_info "✓ Server certificate verified"
    else
        log_error "Server certificate verification failed"
        return 1
    fi

    # Verify client certificate
    if openssl verify -CAfile "$CERTS_DIR/root_ca.crt" "$CERTS_DIR/client.crt" > /dev/null 2>&1; then
        log_info "✓ Client certificate verified"
    else
        log_error "Client certificate verification failed"
        return 1
    fi

    # Verify test-client certificate
    if openssl verify -CAfile "$CERTS_DIR/root_ca.crt" "$CERTS_DIR/test-client.crt" > /dev/null 2>&1; then
        log_info "✓ Test client certificate verified"
    else
        log_error "Test client certificate verification failed"
        return 1
    fi

    return 0
}

# Print summary
print_summary() {
    echo
    echo -e "${GREEN}╭─────────────────────────────────────────────────────╮${NC}"
    echo -e "${GREEN}│        Test Certificates Generated Successfully     │${NC}"
    echo -e "${GREEN}╰─────────────────────────────────────────────────────╯${NC}"
    echo
    echo -e "${YELLOW}Generated certificates:${NC}"
    echo "  CA Certificate:     $CERTS_DIR/root_ca.crt"
    echo "  CA Private Key:     $CERTS_DIR/root_ca.key"
    echo "  Server Certificate: $CERTS_DIR/server.crt"
    echo "  Server Private Key: $CERTS_DIR/server.key"
    echo "  Client Certificate: $CERTS_DIR/client.crt"
    echo "  Client Private Key: $CERTS_DIR/client.key"
    echo "  Test Client Cert:   $CERTS_DIR/test-client.crt"
    echo "  Test Client Key:    $CERTS_DIR/test-client.key"
    echo
    echo -e "${YELLOW}Certificate Details:${NC}"
    echo "  Validity: $CERT_VALIDITY_DAYS days"
    echo "  CA Validity: $CA_VALIDITY_DAYS days"
    echo "  Key Size: 2048 bits (clients/server), 4096 bits (CA)"
    echo
    echo -e "${GREEN}✓ Test environment is ready!${NC}"
    echo
}

# Clean function
clean_certificates() {
    log_warn "Cleaning existing certificates..."
    rm -rf "$CERTS_DIR"
    rm -rf "$STEP_DIR"
    rm -rf "$CONFIG_DIR"
    log_info "✓ Certificates cleaned"
}

# Main function
main() {
    echo -e "${CYAN}"
    echo "╭─────────────────────────────────────────────────────╮"
    echo "│          s01 Test Certificate Generator             │"
    echo "╰─────────────────────────────────────────────────────╯"
    echo -e "${NC}"

    # Parse arguments
    if [[ "${1:-}" == "--clean" ]]; then
        clean_certificates
        exit 0
    fi

    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "Options:"
        echo "  --clean    Remove all generated certificates"
        echo "  --help     Show this help message"
        echo
        echo "This script generates self-signed certificates for the test environment."
        exit 0
    fi

    # Create directories
    create_directories

    # Generate certificates
    generate_ca
    generate_server_cert

    # Generate client certificates
    generate_client_cert "client" "client"
    generate_client_cert "test-client" "test-client"

    # Generate certificates for specific test services
    generate_client_cert "web-01" "web-01"
    generate_client_cert "api-01" "api-01"
    generate_client_cert "db-primary" "db-primary"
    generate_client_cert "worker-01" "worker-01"
    generate_client_cert "worker-02" "worker-02"
    generate_client_cert "load-test-01" "load-test-01"
    generate_client_cert "unhealthy-01" "unhealthy-01"
    generate_client_cert "flapping-01" "flapping-01"

    # Create additional files for compatibility
    create_cert_chain
    create_step_password
    create_step_config

    # Verify certificates
    if verify_certificates; then
        print_summary
    else
        log_error "Certificate verification failed!"
        exit 1
    fi
}

# Run main function
main "$@"
