#!/bin/bash
set -euo pipefail

# Deploy script for Host S01 Service precompiled binaries
# Downloads and installs server and/or client binaries from GitHub releases

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEFAULT_REPO="${S01_REPO:-your-org/s01-service}"  # Set S01_REPO env var or update this default
DEFAULT_VERSION="latest"
DEFAULT_INSTALL_DIR="/opt/s01"
DEFAULT_CONFIG_DIR="/etc/s01"
DEFAULT_CERT_DIR="/etc/ssl/s01"
DEFAULT_DATA_DIR="/var/lib/s01"
DEFAULT_LOG_DIR="/var/log/s01"
DEFAULT_USER="s01"
DEFAULT_GROUP="s01"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Host S01 Service precompiled binaries from GitHub releases

OPTIONS:
    -r, --repo REPO         GitHub repository (default: $DEFAULT_REPO)
    -v, --version VERSION   Version to deploy (default: $DEFAULT_VERSION)
    -s, --server           Deploy s01 server
    -c, --client           Deploy s01 client
    -a, --all              Deploy both server and client
    -i, --install-dir DIR   Installation directory (default: $DEFAULT_INSTALL_DIR)
    --config-dir DIR       Configuration directory (default: $DEFAULT_CONFIG_DIR)
    --cert-dir DIR         Certificate directory (default: $DEFAULT_CERT_DIR)
    --data-dir DIR         Data directory (default: $DEFAULT_DATA_DIR)
    --log-dir DIR          Log directory (default: $DEFAULT_LOG_DIR)
    -u, --user USER        Service user (default: $DEFAULT_USER)
    -g, --group GROUP      Service group (default: $DEFAULT_GROUP)
    --no-systemd           Skip systemd service creation
    --no-certs             Skip certificate setup
    --force                Force overwrite existing installation
    --dry-run              Show what would be done without executing
    --debug                Enable debug output
    -h, --help             Show this help message

EXAMPLES:
    # Deploy server only
    $0 --server --repo myorg/s01-service --version v1.2.3

    # Deploy both server and client
    $0 --all --version latest

    # Deploy client with custom directories
    $0 --client --install-dir /usr/local/s01 --config-dir /usr/local/etc/s01

    # Dry run to see what would be deployed
    $0 --all --dry-run

    # Use environment variable for repo
    S01_REPO=myorg/s01-service $0 --all

ENVIRONMENT VARIABLES:
    S01_REPO  GitHub repository (overrides default)
    GITHUB_TOKEN    GitHub token for private repositories
    DEBUG           Enable debug output (true/false)

EOF
}

# Parse command line arguments
REPO="$DEFAULT_REPO"
VERSION="$DEFAULT_VERSION"
DEPLOY_SERVER=false
DEPLOY_CLIENT=false
INSTALL_DIR="$DEFAULT_INSTALL_DIR"
CONFIG_DIR="$DEFAULT_CONFIG_DIR"
CERT_DIR="$DEFAULT_CERT_DIR"
DATA_DIR="$DEFAULT_DATA_DIR"
LOG_DIR="$DEFAULT_LOG_DIR"
SERVICE_USER="$DEFAULT_USER"
SERVICE_GROUP="$DEFAULT_GROUP"
SETUP_SYSTEMD=true
SETUP_CERTS=true
FORCE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--repo)
            REPO="$2"
            shift 2
            ;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -s|--server)
            DEPLOY_SERVER=true
            shift
            ;;
        -c|--client)
            DEPLOY_CLIENT=true
            shift
            ;;
        -a|--all)
            DEPLOY_SERVER=true
            DEPLOY_CLIENT=true
            shift
            ;;
        -i|--install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --config-dir)
            CONFIG_DIR="$2"
            shift 2
            ;;
        --cert-dir)
            CERT_DIR="$2"
            shift 2
            ;;
        --data-dir)
            DATA_DIR="$2"
            shift 2
            ;;
        --log-dir)
            LOG_DIR="$2"
            shift 2
            ;;
        -u|--user)
            SERVICE_USER="$2"
            shift 2
            ;;
        -g|--group)
            SERVICE_GROUP="$2"
            shift 2
            ;;
        --no-systemd)
            SETUP_SYSTEMD=false
            shift
            ;;
        --no-certs)
            SETUP_CERTS=false
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate arguments
if [[ "$DEPLOY_SERVER" == false && "$DEPLOY_CLIENT" == false ]]; then
    log_error "Must specify --server, --client, or --all"
    usage
    exit 1
fi

# Check if running as root for system installation
if [[ "$INSTALL_DIR" == /opt/* ]] || [[ "$CONFIG_DIR" == /etc/* ]] && [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root for system-wide installation"
    exit 1
fi

# Functions

check_dependencies() {
    log_info "Checking dependencies..."

    local deps=("curl" "tar" "jq")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "Required dependency '$dep' is not installed"
            exit 1
        fi
    done

    if [[ "$SETUP_SYSTEMD" == true ]] && ! command -v systemctl &> /dev/null; then
        log_warn "systemctl not found, disabling systemd service setup"
        SETUP_SYSTEMD=false
    fi
}

get_latest_version() {
    log_info "Getting latest version from GitHub..."

    local auth_header=""
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth_header="-H Authorization: token $GITHUB_TOKEN"
    fi

    local api_url="https://api.github.com/repos/$REPO/releases/latest"
    local latest_version
    latest_version=$(curl -s $auth_header "$api_url" | jq -r '.tag_name')

    if [[ "$latest_version" == "null" ]] || [[ -z "$latest_version" ]]; then
        log_error "Failed to get latest version from $REPO"
        exit 1
    fi

    echo "$latest_version"
}

download_binary() {
    local component="$1"
    local version="$2"
    local temp_dir="$3"

    log_info "Downloading $component binary version $version..."

    local auth_header=""
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth_header="-H Authorization: token $GITHUB_TOKEN"
    fi

    # Construct download URL - adjust this based on your release naming convention
    local binary_name="s01-${component}-linux-amd64"
    local download_url="https://github.com/$REPO/releases/download/$version/$binary_name.tar.gz"

    log_debug "Download URL: $download_url"

    if [[ "$DRY_RUN" == false ]]; then
        if ! curl -L -f $auth_header "$download_url" -o "$temp_dir/${component}.tar.gz"; then
            log_error "Failed to download $component binary from $download_url"
            return 1
        fi

        # Extract binary
        cd "$temp_dir"
        if ! tar -xzf "${component}.tar.gz"; then
            log_error "Failed to extract $component binary"
            return 1
        fi

        # Find the actual binary (it might be in a subdirectory)
        local binary_path
        binary_path=$(find . -name "s01-${component}" -type f -executable | head -1)

        if [[ -z "$binary_path" ]]; then
            log_error "Could not find s01-${component} executable in downloaded archive"
            return 1
        fi

        mv "$binary_path" "s01-${component}"
        chmod +x "s01-${component}"
    fi

    log_info "$component binary downloaded successfully"
    return 0
}

create_user() {
    log_info "Creating service user and group..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create user $SERVICE_USER and group $SERVICE_GROUP"
        return 0
    fi

    if ! getent group "$SERVICE_GROUP" >/dev/null 2>&1; then
        groupadd --system "$SERVICE_GROUP"
        log_info "Created group: $SERVICE_GROUP"
    fi

    if ! getent passwd "$SERVICE_USER" >/dev/null 2>&1; then
        useradd --system --gid "$SERVICE_GROUP" --home-dir "$DATA_DIR" \
                --shell /bin/false --comment "S01 Service" "$SERVICE_USER"
        log_info "Created user: $SERVICE_USER"
    fi
}

create_directories() {
    log_info "Creating directories..."

    local dirs=("$INSTALL_DIR" "$CONFIG_DIR" "$CERT_DIR" "$DATA_DIR" "$LOG_DIR")

    for dir in "${dirs[@]}"; do
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would create directory: $dir"
        else
            mkdir -p "$dir"
            chown "$SERVICE_USER:$SERVICE_GROUP" "$dir"
            chmod 755 "$dir"
            log_debug "Created directory: $dir"
        fi
    done
}

install_binary() {
    local component="$1"
    local temp_dir="$2"

    log_info "Installing $component binary..."

    local binary_path="$INSTALL_DIR/s01-$component"

    if [[ -f "$binary_path" ]] && [[ "$FORCE" == false ]]; then
        log_error "$component binary already exists at $binary_path (use --force to overwrite)"
        return 1
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would install $component binary to $binary_path"
        return 0
    fi

    cp "$temp_dir/s01-$component" "$binary_path"
    chown "$SERVICE_USER:$SERVICE_GROUP" "$binary_path"
    chmod 755 "$binary_path"

    log_info "$component binary installed to $binary_path"
}

create_config_files() {
    local component="$1"

    log_info "Creating default configuration for $component..."

    local config_file="$CONFIG_DIR/$component.conf"

    if [[ -f "$config_file" ]] && [[ "$FORCE" == false ]]; then
        log_info "Configuration file already exists: $config_file"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create configuration file: $config_file"
        return 0
    fi

    if [[ "$component" == "server" ]]; then
        cat > "$config_file" << EOF
# S01 Server Configuration
SERVER_PORT=8443
HEALTH_PORT=8080
MAX_HISTORY=1000
STALE_TIMEOUT=600
CERT_FILE=$CERT_DIR/server.crt
KEY_FILE=$CERT_DIR/server.key
CA_CERT_FILE=$CERT_DIR/ca.crt
LOG_LEVEL=info
LOG_FILE=$LOG_DIR/server.log
DATA_DIR=$DATA_DIR
EOF
    elif [[ "$component" == "client" ]]; then
        cat > "$config_file" << EOF
# S01 Client Configuration
SERVICE_NAME=my-service
INSTANCE_NAME=\$(hostname)
SERVER_URL=https://localhost:8443
CERT_FILE=$CERT_DIR/client.crt
KEY_FILE=$CERT_DIR/client.key
CA_CERT_FILE=$CERT_DIR/ca.crt
LOG_LEVEL=info
LOG_FILE=$LOG_DIR/client.log
REPORT_INTERVAL=30
TIMEOUT=30
RETRY_ATTEMPTS=3
RETRY_DELAY=5
HEALTH_CPU_THRESHOLD=80.0
HEALTH_MEMORY_THRESHOLD=85.0
HEALTH_DISK_THRESHOLD=85.0
HEALTH_NETWORK_ENABLED=true
HEALTH_SCORE_HEALTHY_MIN=80
HEALTH_SCORE_DEGRADED_MIN=60
EOF
    fi

    chown "$SERVICE_USER:$SERVICE_GROUP" "$config_file"
    chmod 640 "$config_file"

    log_info "Configuration file created: $config_file"
}

create_systemd_service() {
    local component="$1"

    if [[ "$SETUP_SYSTEMD" == false ]]; then
        return 0
    fi

    log_info "Creating systemd service for $component..."

    local service_file="/etc/systemd/system/s01-$component.service"
    local binary_path="$INSTALL_DIR/s01-$component"
    local config_file="$CONFIG_DIR/$component.conf"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create systemd service: $service_file"
        return 0
    fi

    local description="Host S01 Service"
    local after_service=""
    local wants_service=""

    if [[ "$component" == "server" ]]; then
        description="Host S01 Server"
        after_service="network.target"
    elif [[ "$component" == "client" ]]; then
        description="Host S01 Client"
        after_service="network.target"
        if [[ "$DEPLOY_SERVER" == true ]]; then
            wants_service="s01-server.service"
            after_service="network.target s01-server.service"
        fi
    fi

    cat > "$service_file" << EOF
[Unit]
Description=$description
Documentation=https://github.com/$REPO
After=$after_service
$([ -n "$wants_service" ] && echo "Wants=$wants_service")

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
ExecStart=$binary_path
EnvironmentFile=$config_file
WorkingDirectory=$DATA_DIR
StandardOutput=journal
StandardError=journal
SyslogIdentifier=s01-$component
Restart=always
RestartSec=10
TimeoutStopSec=30
KillMode=mixed
KillSignal=SIGTERM

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$DATA_DIR $LOG_DIR $CERT_DIR
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictRealtime=true
RestrictNamespaces=true

# Resource limits
LimitNOFILE=65536
MemoryMax=1G

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_info "Systemd service created: $service_file"

    if [[ "$component" == "server" ]]; then
        log_info "To start the server: systemctl start s01-server"
        log_info "To enable on boot: systemctl enable s01-server"
    elif [[ "$component" == "client" ]]; then
        log_info "To start the client: systemctl start s01-client"
        log_info "To enable on boot: systemctl enable s01-client"
    fi
}

setup_certificates() {
    if [[ "$SETUP_CERTS" == false ]]; then
        return 0
    fi

    log_info "Setting up certificate directories..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would set up certificate directories in $CERT_DIR"
        return 0
    fi

    # Create certificate directory structure
    mkdir -p "$CERT_DIR"
    chown "$SERVICE_USER:$SERVICE_GROUP" "$CERT_DIR"
    chmod 750 "$CERT_DIR"

    # Create placeholder certificate files if they don't exist
    local cert_files=("ca.crt")

    if [[ "$DEPLOY_SERVER" == true ]]; then
        cert_files+=("server.crt" "server.key")
    fi

    if [[ "$DEPLOY_CLIENT" == true ]]; then
        cert_files+=("client.crt" "client.key")
    fi

    for cert_file in "${cert_files[@]}"; do
        local cert_path="$CERT_DIR/$cert_file"
        if [[ ! -f "$cert_path" ]]; then
            touch "$cert_path"
            chown "$SERVICE_USER:$SERVICE_GROUP" "$cert_path"
            if [[ "$cert_file" == *.key ]]; then
                chmod 600 "$cert_path"
            else
                chmod 644 "$cert_path"
            fi
        fi
    done

    cat > "$CERT_DIR/README.txt" << EOF
Certificate Directory for S01 Service

This directory should contain the following certificate files:

ca.crt      - Certificate Authority root certificate
server.crt  - Server certificate (for s01-server)
server.key  - Server private key (for s01-server)
client.crt  - Client certificate (for s01-client)
client.key  - Client private key (for s01-client)

Please obtain proper certificates from your CA before starting the services.

For development, you can use the Step CA setup in the Docker environment
to generate these certificates.
EOF

    chown "$SERVICE_USER:$SERVICE_GROUP" "$CERT_DIR/README.txt"
    chmod 644 "$CERT_DIR/README.txt"

    log_warn "Placeholder certificate files created. Please install proper certificates before starting services."
}

cleanup_temp_files() {
    local temp_dir="$1"

    if [[ -d "$temp_dir" ]]; then
        rm -rf "$temp_dir"
        log_debug "Cleaned up temporary directory: $temp_dir"
    fi
}

print_summary() {
    log_info "Deployment completed successfully!"
    echo
    echo "Installation Summary:"
    echo "===================="
    echo "Repository: $REPO"
    echo "Version: $VERSION"
    echo "Install Directory: $INSTALL_DIR"
    echo "Config Directory: $CONFIG_DIR"
    echo "Certificate Directory: $CERT_DIR"
    echo "Data Directory: $DATA_DIR"
    echo "Log Directory: $LOG_DIR"
    echo "Service User: $SERVICE_USER"
    echo "Service Group: $SERVICE_GROUP"
    echo

    if [[ "$DEPLOY_SERVER" == true ]]; then
        echo "Server binary: $INSTALL_DIR/s01-server"
        echo "Server config: $CONFIG_DIR/server.conf"
        if [[ "$SETUP_SYSTEMD" == true ]]; then
            echo "Server service: s01-server.service"
        fi
    fi

    if [[ "$DEPLOY_CLIENT" == true ]]; then
        echo "Client binary: $INSTALL_DIR/s01-client"
        echo "Client config: $CONFIG_DIR/client.conf"
        if [[ "$SETUP_SYSTEMD" == true ]]; then
            echo "Client service: s01-client.service"
        fi
    fi

    echo
    echo "Next Steps:"
    echo "==========="
    echo "1. Install proper certificates in $CERT_DIR/"
    echo "2. Review and customize configuration files in $CONFIG_DIR/"

    if [[ "$SETUP_SYSTEMD" == true ]]; then
        if [[ "$DEPLOY_SERVER" == true ]]; then
            echo "3. Start server: systemctl start s01-server"
            echo "4. Enable server on boot: systemctl enable s01-server"
        fi
        if [[ "$DEPLOY_CLIENT" == true ]]; then
            echo "3. Start client: systemctl start s01-client"
            echo "4. Enable client on boot: systemctl enable s01-client"
        fi
        echo "5. Check status: systemctl status s01-server s01-client"
        echo "6. View logs: journalctl -u s01-server -u s01-client -f"
    else
        echo "3. Start services manually using the installed binaries"
    fi
}

# Main execution
main() {
    log_info "Starting deployment of S01 Service binaries..."
    log_debug "Repository: $REPO"
    log_debug "Version: $VERSION"
    log_debug "Deploy Server: $DEPLOY_SERVER"
    log_debug "Deploy Client: $DEPLOY_CLIENT"
    log_debug "Install Directory: $INSTALL_DIR"

    # Resolve version
    if [[ "$VERSION" == "latest" ]]; then
        VERSION=$(get_latest_version)
        log_info "Resolved latest version to: $VERSION"
    fi

    # Check dependencies
    check_dependencies

    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "cleanup_temp_files '$temp_dir'" EXIT

    # Download binaries
    if [[ "$DEPLOY_SERVER" == true ]]; then
        download_binary "server" "$VERSION" "$temp_dir"
    fi

    if [[ "$DEPLOY_CLIENT" == true ]]; then
        download_binary "client" "$VERSION" "$temp_dir"
    fi

    # Create user and directories
    create_user
    create_directories
    setup_certificates

    # Install binaries and create configs
    if [[ "$DEPLOY_SERVER" == true ]]; then
        install_binary "server" "$temp_dir"
        create_config_files "server"
        create_systemd_service "server"
    fi

    if [[ "$DEPLOY_CLIENT" == true ]]; then
        install_binary "client" "$temp_dir"
        create_config_files "client"
        create_systemd_service "client"
    fi

    # Print summary
    print_summary
}

# Execute main function
main "$@"
