#!/bin/bash
set -euo pipefail

# Host Discovery Service - One-liner Installation Script
# Usage: curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/YOUR_REPO/main/install.sh | bash
# Or:    wget -qO- https://raw.githubusercontent.com/YOUR_ORG/YOUR_REPO/main/install.sh | bash

# Configuration - UPDATE THESE VALUES FOR YOUR REPOSITORY
GITHUB_REPO="${DISCOVERY_REPO:-your-org/discovery-service}"
DEFAULT_VERSION="latest"
INSTALL_PREFIX="/usr/local"
CONFIG_DIR="$HOME/.config/discovery"
SERVICE_USER="$USER"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Banner
print_banner() {
    echo -e "${CYAN}"
    echo "╭─────────────────────────────────────────────────────╮"
    echo "│          Host Discovery Service Installer           │"
    echo "│                                                     │"
    echo "│  One-liner installation from GitHub releases        │"
    echo "╰─────────────────────────────────────────────────────╯"
    echo -e "${NC}"
}

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

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Usage information
usage() {
    cat << EOF
${GREEN}Host Discovery Service - One-liner Installer${NC}

${YELLOW}USAGE:${NC}
  curl -fsSL https://raw.githubusercontent.com/$GITHUB_REPO/main/install.sh | bash
  wget -qO- https://raw.githubusercontent.com/$GITHUB_REPO/main/install.sh | bash

${YELLOW}OPTIONS:${NC}
  --server-only         Install discovery server only
  --client-only         Install discovery client only
  --version VERSION     Install specific version (default: latest)
  --repo REPO           Use different GitHub repository
  --prefix PATH         Install to custom prefix (default: $INSTALL_PREFIX)
  --system             Install system-wide (requires sudo)
  --help               Show this help message

${YELLOW}EXAMPLES:${NC}
  # Install both server and client
  curl -fsSL https://raw.githubusercontent.com/$GITHUB_REPO/main/install.sh | bash

  # Install server only
  curl -fsSL https://raw.githubusercontent.com/$GITHUB_REPO/main/install.sh | bash -s -- --server-only

  # Install specific version
  curl -fsSL https://raw.githubusercontent.com/$GITHUB_REPO/main/install.sh | bash -s -- --version v1.2.3

  # System-wide installation
  curl -fsSL https://raw.githubusercontent.com/$GITHUB_REPO/main/install.sh | sudo bash -s -- --system

${YELLOW}ENVIRONMENT VARIABLES:${NC}
  DISCOVERY_REPO        Override GitHub repository
  GITHUB_TOKEN          GitHub token for private repositories

EOF
}

# Check dependencies
check_dependencies() {
    local missing_deps=()

    for cmd in curl tar; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_info "Please install: ${missing_deps[*]}"
        exit 1
    fi
}

# Detect system architecture
detect_arch() {
    local arch
    arch="$(uname -m)"

    case "$arch" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l) echo "arm" ;;
        *)
            log_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}

# Get latest version from GitHub
get_latest_version() {
    log_info "Getting latest version from GitHub..."

    local auth_header=""
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth_header="-H Authorization: token $GITHUB_TOKEN"
    fi

    local version
    version=$(curl -s $auth_header "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | \
              grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [[ -z "$version" || "$version" == "null" ]]; then
        log_error "Failed to get latest version from $GITHUB_REPO"
        log_error "Please check if the repository exists and has releases"
        exit 1
    fi

    echo "$version"
}

# Download and extract binary
download_binary() {
    local component="$1"
    local version="$2"
    local arch="$3"
    local temp_dir="$4"

    log_info "Downloading $component binary (version: $version, arch: $arch)..."

    local binary_name="discovery-${component}-linux-${arch}"
    local download_url="https://github.com/$GITHUB_REPO/releases/download/$version/${binary_name}.tar.gz"

    local auth_header=""
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth_header="-H Authorization: token $GITHUB_TOKEN"
    fi

    log_debug "Download URL: $download_url"

    if ! curl -fsSL $auth_header "$download_url" -o "$temp_dir/${component}.tar.gz"; then
        log_error "Failed to download $component binary"
        log_error "URL: $download_url"
        log_error "This could mean:"
        log_error "  - Release doesn't exist for version $version"
        log_error "  - Binary not available for architecture $arch"
        log_error "  - Repository is private and needs GITHUB_TOKEN"
        return 1
    fi

    # Extract binary
    if ! tar -xzf "$temp_dir/${component}.tar.gz" -C "$temp_dir"; then
        log_error "Failed to extract $component binary"
        return 1
    fi

    # Find the binary file
    local binary_file
    binary_file=$(find "$temp_dir" -name "discovery-${component}" -type f | head -1)

    if [[ ! -f "$binary_file" ]]; then
        log_error "Could not find discovery-${component} executable in downloaded archive"
        return 1
    fi

    # Make executable
    chmod +x "$binary_file"

    log_info "✓ $component binary downloaded and extracted"
    echo "$binary_file"
}

# Install binary
install_binary() {
    local binary_path="$1"
    local component="$2"
    local install_dir="$3"

    local target_path="$install_dir/discovery-$component"

    log_info "Installing $component to $target_path..."

    # Create install directory if it doesn't exist
    mkdir -p "$install_dir"

    # Copy binary
    cp "$binary_path" "$target_path"
    chmod +x "$target_path"

    # Verify installation
    if "$target_path" --version >/dev/null 2>&1 || "$target_path" --help >/dev/null 2>&1; then
        log_info "✓ $component installed successfully"
        return 0
    else
        log_warn "⚠ $component installed but verification failed"
        return 0
    fi
}

# Create basic configuration
create_config() {
    local component="$1"

    mkdir -p "$CONFIG_DIR"

    local config_file="$CONFIG_DIR/${component}.env"

    if [[ -f "$config_file" ]]; then
        log_info "Configuration already exists: $config_file"
        return 0
    fi

    log_info "Creating basic configuration for $component..."

    if [[ "$component" == "server" ]]; then
        cat > "$config_file" << EOF
# Discovery Server Configuration
# Edit this file to customize settings

SERVER_PORT=8443
HEALTH_PORT=8080
MAX_HISTORY=100
STALE_TIMEOUT=300
LOG_LEVEL=info

# Certificate files (update paths as needed)
# CERT_FILE=/path/to/server.crt
# KEY_FILE=/path/to/server.key
# CA_CERT_FILE=/path/to/ca.crt
EOF
    elif [[ "$component" == "client" ]]; then
        cat > "$config_file" << EOF
# Discovery Client Configuration
# Edit this file to customize settings

SERVICE_NAME=my-service
INSTANCE_NAME=$(hostname)
SERVER_URL=https://localhost:8443
LOG_LEVEL=info
REPORT_INTERVAL=30
TIMEOUT=30

# Certificate files (update paths as needed)
# CERT_FILE=/path/to/client.crt
# KEY_FILE=/path/to/client.key
# CA_CERT_FILE=/path/to/ca.crt

# Health monitoring thresholds
HEALTH_CPU_THRESHOLD=80.0
HEALTH_MEMORY_THRESHOLD=85.0
HEALTH_DISK_THRESHOLD=85.0
HEALTH_NETWORK_ENABLED=true
EOF
    fi

    log_info "✓ Configuration created: $config_file"
}

# Create wrapper scripts
create_wrapper() {
    local component="$1"
    local install_dir="$2"
    local binary_path="$install_dir/discovery-$component"
    local wrapper_path="$install_dir/discovery-$component-run"

    log_debug "Creating wrapper script: $wrapper_path"

    cat > "$wrapper_path" << EOF
#!/bin/bash
# Discovery $component wrapper script
# Auto-generated by installer

CONFIG_FILE="$CONFIG_DIR/${component}.env"

# Source configuration if it exists
if [[ -f "\$CONFIG_FILE" ]]; then
    set -a  # Export all variables
    source "\$CONFIG_FILE"
    set +a
fi

# Run the binary
exec "$binary_path" "\$@"
EOF

    chmod +x "$wrapper_path"
    log_debug "✓ Wrapper created: $wrapper_path"
}

# Print installation summary
print_summary() {
    local installed_components=("$@")

    echo
    echo -e "${GREEN}╭─────────────────────────────────────────────────────╮${NC}"
    echo -e "${GREEN}│                Installation Complete!               │${NC}"
    echo -e "${GREEN}╰─────────────────────────────────────────────────────╯${NC}"
    echo

    echo -e "${YELLOW}Installed Components:${NC}"
    for component in "${installed_components[@]}"; do
        echo -e "  ${GREEN}✓${NC} Discovery $component"
    done

    echo
    echo -e "${YELLOW}Installation Details:${NC}"
    echo -e "  Binaries: ${INSTALL_PREFIX}/bin/"
    echo -e "  Config:   ${CONFIG_DIR}/"
    echo -e "  Version:  ${VERSION}"

    echo
    echo -e "${YELLOW}Quick Start:${NC}"

    if [[ " ${installed_components[*]} " =~ " server " ]]; then
        echo -e "${CYAN}Server:${NC}"
        echo -e "  # Start server (requires certificates)"
        echo -e "  ${INSTALL_PREFIX}/bin/discovery-server-run"
        echo -e "  # Or with custom config:"
        echo -e "  ${INSTALL_PREFIX}/bin/discovery-server --help"
        echo
    fi

    if [[ " ${installed_components[*]} " =~ " client " ]]; then
        echo -e "${CYAN}Client:${NC}"
        echo -e "  # Start client (configure SERVER_URL in config first)"
        echo -e "  ${INSTALL_PREFIX}/bin/discovery-client-run"
        echo -e "  # Or with custom config:"
        echo -e "  ${INSTALL_PREFIX}/bin/discovery-client --help"
        echo
    fi

    echo -e "${YELLOW}Configuration:${NC}"
    echo -e "  Edit configuration files in: ${CONFIG_DIR}/"
    for component in "${installed_components[@]}"; do
        echo -e "    ${CONFIG_DIR}/${component}.env"
    done

    echo
    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "  ${BLUE}1.${NC} Configure certificates (if using HTTPS)"
    echo -e "  ${BLUE}2.${NC} Edit configuration files as needed"
    echo -e "  ${BLUE}3.${NC} Start the services"

    if [[ "$SYSTEM_INSTALL" == "true" ]]; then
        echo -e "  ${BLUE}4.${NC} Consider creating systemd services for automatic startup"
    fi

    echo
    echo -e "${GREEN}For more information:${NC}"
    echo -e "  Repository: https://github.com/$GITHUB_REPO"
    echo -e "  Documentation: https://github.com/$GITHUB_REPO#readme"
    echo
}

# Parse command line arguments
INSTALL_SERVER=true
INSTALL_CLIENT=true
VERSION="$DEFAULT_VERSION"
SYSTEM_INSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --server-only)
            INSTALL_SERVER=true
            INSTALL_CLIENT=false
            shift
            ;;
        --client-only)
            INSTALL_SERVER=false
            INSTALL_CLIENT=true
            shift
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --repo)
            GITHUB_REPO="$2"
            shift 2
            ;;
        --prefix)
            INSTALL_PREFIX="$2"
            shift 2
            ;;
        --system)
            SYSTEM_INSTALL=true
            INSTALL_PREFIX="/usr/local"
            CONFIG_DIR="/etc/discovery"
            SERVICE_USER="root"
            shift
            ;;
        --help|-h)
            print_banner
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Main installation function
main() {
    print_banner

    # Check if we need sudo for system installation
    if [[ "$SYSTEM_INSTALL" == "true" && $EUID -ne 0 ]]; then
        log_error "System installation requires root privileges"
        log_info "Please run with sudo or use --prefix for user installation"
        exit 1
    fi

    # Validate repository format
    if [[ ! "$GITHUB_REPO" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
        log_error "Invalid repository format: $GITHUB_REPO"
        log_error "Expected format: owner/repository-name"
        exit 1
    fi

    log_info "Installing Host Discovery Service"
    log_info "Repository: $GITHUB_REPO"
    log_info "Install prefix: $INSTALL_PREFIX"

    # Check dependencies
    check_dependencies

    # Detect architecture
    local arch
    arch=$(detect_arch)
    log_info "Detected architecture: $arch"

    # Get version
    if [[ "$VERSION" == "latest" ]]; then
        VERSION=$(get_latest_version)
        log_info "Latest version: $VERSION"
    else
        log_info "Using version: $VERSION"
    fi

    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf '$temp_dir'" EXIT

    # Install directory
    local bin_dir="$INSTALL_PREFIX/bin"
    mkdir -p "$bin_dir"

    local installed_components=()

    # Download and install server
    if [[ "$INSTALL_SERVER" == "true" ]]; then
        local server_binary
        if server_binary=$(download_binary "server" "$VERSION" "$arch" "$temp_dir"); then
            install_binary "$server_binary" "server" "$bin_dir"
            create_config "server"
            create_wrapper "server" "$bin_dir"
            installed_components+=("server")
        else
            log_error "Failed to install server"
            exit 1
        fi
    fi

    # Download and install client
    if [[ "$INSTALL_CLIENT" == "true" ]]; then
        local client_binary
        if client_binary=$(download_binary "client" "$VERSION" "$arch" "$temp_dir"); then
            install_binary "$client_binary" "client" "$bin_dir"
            create_config "client"
            create_wrapper "client" "$bin_dir"
            installed_components+=("client")
        else
            log_error "Failed to install client"
            exit 1
        fi
    fi

    # Add to PATH if not already there
    if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
        log_info "Adding $bin_dir to PATH"

        # Determine shell configuration file
        local shell_config=""
        if [[ -f "$HOME/.bashrc" ]]; then
            shell_config="$HOME/.bashrc"
        elif [[ -f "$HOME/.zshrc" ]]; then
            shell_config="$HOME/.zshrc"
        elif [[ -f "$HOME/.profile" ]]; then
            shell_config="$HOME/.profile"
        fi

        if [[ -n "$shell_config" && "$SYSTEM_INSTALL" == "false" ]]; then
            echo "export PATH=\"$bin_dir:\$PATH\"" >> "$shell_config"
            log_info "Added to PATH in $shell_config"
            log_warn "Please run: source $shell_config (or restart your terminal)"
        fi
    fi

    # Print summary
    print_summary "${installed_components[@]}"

    # Final verification
    log_info "Installation completed successfully!"

    return 0
}

# Run main function with all arguments
main "$@"
