#!/bin/bash
set -euo pipefail

# s01 - One-liner Installation Script
# Usage: curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/YOUR_REPO/main/install.sh | bash
# Or:    wget -qO- https://raw.githubusercontent.com/YOUR_ORG/YOUR_REPO/main/install.sh | bash

# Configuration
GITHUB_REPO="${DISCOVERY_REPO:-k1t-ops/s01}"
DEFAULT_VERSION="latest"
INSTALL_PREFIX="/usr/local"
CONFIG_DIR="$HOME/.config/s01"
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
  --server-only         Install s01 server only
  --client-only         Install s01 client only
  --version VERSION     Install specific version (default: latest)
  --repo REPO           Use different GitHub repository
  --prefix PATH         Install to custom prefix (default: $INSTALL_PREFIX)
  --system             Install system-wide (requires sudo)
  --diagnose           Show system diagnostics and exit
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
    local raw_arch
    raw_arch="$(uname -m 2>/dev/null)"

    if [[ -z "$raw_arch" ]]; then
        log_error "Cannot detect system architecture"
        log_error "Please specify architecture manually or check system compatibility"
        exit 1
    fi

    local normalized_arch
    case "$raw_arch" in
        x86_64|amd64)
            normalized_arch="amd64"
            ;;
        aarch64|arm64)
            normalized_arch="arm64"
            ;;
        armv7l|armv7*)
            normalized_arch="arm"
            ;;
        i386|i686)
            log_error "32-bit x86 architecture ($raw_arch) is not supported"
            log_error "This installer requires 64-bit systems"
            log_error "Supported architectures: x86_64 (amd64), aarch64 (arm64), armv7l (arm)"
            exit 1
            ;;
        *)
            log_error "Unsupported architecture: $raw_arch"
            echo
            log_error "Supported architectures:"
            log_error "  • x86_64 (Intel/AMD 64-bit) → amd64 binaries"
            log_error "  • aarch64 (ARM 64-bit) → arm64 binaries"
            log_error "  • armv7l (ARM 32-bit) → arm binaries"
            echo
            log_error "If you believe this architecture should be supported,"
            log_error "please open an issue at: https://github.com/$GITHUB_REPO/issues"
            exit 1
            ;;
    esac

    log_debug "Detected architecture: $raw_arch → $normalized_arch"
    echo "$normalized_arch"
}

# Get latest version from GitHub
get_latest_version() {
    local auth_header=""
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth_header="-H Authorization: token $GITHUB_TOKEN"
    fi

    log_debug "Fetching latest version from GitHub API..."

    # Check if we can reach GitHub first
    if ! curl -s --connect-timeout 10 https://api.github.com > /dev/null 2>&1; then
        log_error "Cannot connect to GitHub API"
        log_error "Please check your internet connection and try again"
        exit 1
    fi

    local api_response
    api_response=$(curl -s $auth_header "https://api.github.com/repos/$GITHUB_REPO/releases/latest" 2>/dev/null)

    # Check if we got a valid response
    if [[ -z "$api_response" ]]; then
        log_error "No response from GitHub API"
        log_error "Repository: https://github.com/$GITHUB_REPO"
        exit 1
    fi

    # Check for API errors
    if echo "$api_response" | grep -q '"message".*"Not Found"'; then
        log_error "Repository not found: $GITHUB_REPO"
        echo
        log_error "Please check:"
        log_error "  • Repository name is correct"
        log_error "  • Repository exists at: https://github.com/$GITHUB_REPO"
        log_error "  • Repository is public (or set GITHUB_TOKEN for private repos)"
        exit 1
    fi

    local version
    version=$(echo "$api_response" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | head -1)

    if [[ -z "$version" || "$version" == "null" ]]; then
        log_error "No releases found for repository: $GITHUB_REPO"
        echo
        log_error "The repository exists but has no published releases."
        log_error "Please ask the maintainer to create a release with binaries."
        log_error "Releases page: https://github.com/$GITHUB_REPO/releases"
        exit 1
    fi

    log_info "Found latest version: $version"
    echo "$version"
}

# Download and extract binary
download_binary() {
    local component="$1"
    local version="$2"
    local arch="$3"
    local temp_dir="$4"

    local binary_name="s01-${component}-linux-${arch}"
    local download_url="https://github.com/$GITHUB_REPO/releases/download/$version/${binary_name}.tar.gz"

    log_info "Downloading $component binary..."
    log_debug "  Version: $version"
    log_debug "  Architecture: $arch"
    log_debug "  URL: $download_url"

    local auth_header=""
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth_header="-H Authorization: token $GITHUB_TOKEN"
    fi

    # Test if URL is accessible first
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" $auth_header "$download_url" 2>/dev/null)

    case "$http_code" in
        200)
            log_debug "Download URL is accessible"
            ;;
        404)
            log_error "Binary not found: $binary_name.tar.gz"
            echo
            log_error "This means:"
            log_error "  • Release $version exists but doesn't have binaries for $arch architecture"
            log_error "  • Check available files at: https://github.com/$GITHUB_REPO/releases/tag/$version"
            echo
            log_error "Supported architectures are typically: amd64, arm64, arm"
            return 1
            ;;
        403)
            log_error "Access denied to repository: $GITHUB_REPO"
            echo
            log_error "This means:"
            log_error "  • Repository is private and requires authentication"
            log_error "  • Set GITHUB_TOKEN environment variable with a valid token"
            return 1
            ;;
        *)
            log_error "Cannot access release (HTTP $http_code)"
            log_error "URL: $download_url"
            echo
            log_error "Check if:"
            log_error "  • Repository exists: https://github.com/$GITHUB_REPO"
            log_error "  • Release $version exists"
            log_error "  • Internet connection is working"
            return 1
            ;;
    esac

    # Download the file
    if ! curl -fsSL $auth_header "$download_url" -o "$temp_dir/${component}.tar.gz" 2>/dev/null; then
        log_error "Download failed despite accessibility check"
        log_error "URL: $download_url"
        return 1
    fi

    # Extract binary
    if ! tar -xzf "$temp_dir/${component}.tar.gz" -C "$temp_dir" 2>/dev/null; then
        log_error "Failed to extract downloaded archive"
        log_error "The downloaded file may be corrupted"
        return 1
    fi

    # Find the binary file
    local binary_file
    binary_file=$(find "$temp_dir" -name "s01-${component}" -type f | head -1)

    if [[ ! -f "$binary_file" ]]; then
        log_error "Archive extracted but no executable found"
        log_error "Expected: s01-${component}"
        log_error "Archive contents:"
        tar -tzf "$temp_dir/${component}.tar.gz" | head -5
        return 1
    fi

    # Make executable
    chmod +x "$binary_file"

    log_info "✓ $component binary ready"
    echo "$binary_file"
}

# Diagnose system for troubleshooting
diagnose_system() {
    echo -e "${CYAN}System Diagnostics${NC}"
    echo "=================="
    echo

    echo "System Information:"
    echo "  OS: $(uname -s 2>/dev/null || echo 'Unknown')"
    echo "  Architecture: $(uname -m 2>/dev/null || echo 'Unknown')"
    echo "  Kernel: $(uname -r 2>/dev/null || echo 'Unknown')"
    echo

    echo "Network Connectivity:"
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        echo "  Internet: ✓ Connected"
    else
        echo "  Internet: ✗ No connection"
    fi

    if curl -s --connect-timeout 5 https://api.github.com >/dev/null 2>&1; then
        echo "  GitHub API: ✓ Accessible"
    else
        echo "  GitHub API: ✗ Cannot connect"
    fi
    echo

    echo "Repository Information:"
    echo "  Repository: $GITHUB_REPO"
    echo "  Releases URL: https://github.com/$GITHUB_REPO/releases"
    echo

    echo "Architecture Mapping:"
    local raw_arch=$(uname -m 2>/dev/null || echo "unknown")
    echo "  Raw: $raw_arch"
    case "$raw_arch" in
        x86_64|amd64) echo "  Normalized: amd64" ;;
        aarch64|arm64) echo "  Normalized: arm64" ;;
        armv7l|armv7*) echo "  Normalized: arm" ;;
        *) echo "  Normalized: UNSUPPORTED" ;;
    esac
    echo

    echo "Available Tools:"
    for tool in curl tar; do
        if command -v "$tool" >/dev/null 2>&1; then
            echo "  $tool: ✓ Available"
        else
            echo "  $tool: ✗ Missing"
        fi
    done
    echo

    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "Authentication: ✓ GITHUB_TOKEN set"
    else
        echo "Authentication: No GITHUB_TOKEN (OK for public repos)"
    fi
    echo
}

# Download with architecture fallback
download_with_fallback() {
    local component="$1"
    local version="$2"
    local primary_arch="$3"
    local temp_dir="$4"

    # Try primary architecture first
    if download_binary "$component" "$version" "$primary_arch" "$temp_dir"; then
        return 0
    fi

    log_warn "$component binary not available for $primary_arch architecture"

    # Define fallback architectures based on primary
    local fallback_archs=()
    case "$primary_arch" in
        arm64)
            fallback_archs=("amd64")
            log_info "Trying fallback: ARM64 → AMD64 (may work with emulation)"
            ;;
        arm)
            fallback_archs=("amd64")
            log_info "Trying fallback: ARM → AMD64 (may work with emulation)"
            ;;
        amd64)
            # No fallbacks for amd64 as it's the most common
            ;;
    esac

    # Try fallback architectures
    if [ ${#fallback_archs[@]} -gt 0 ]; then
        for fallback_arch in "${fallback_archs[@]}"; do
            log_info "Attempting download with $fallback_arch architecture..."
            if download_binary "$component" "$version" "$fallback_arch" "$temp_dir"; then
                log_warn "Using $fallback_arch binary instead of $primary_arch"
                log_warn "This may work but is not optimal for your system"
                return 0
            fi
        done
    fi

    log_error "No compatible binary found for any architecture"
    echo
    log_error "Tried architectures: $primary_arch${fallback_archs:+ ${fallback_archs[*]}}"
    log_error "Check available releases: https://github.com/$GITHUB_REPO/releases/tag/$version"
    return 1
}

# Install binary
install_binary() {
    local binary_path="$1"
    local component="$2"
    local install_dir="$3"

    local target_path="$install_dir/s01-$component"

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
# s01 Server Configuration
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
# s01 Client Configuration
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
    local binary_path="$install_dir/s01-$component"
    local wrapper_path="$install_dir/s01-$component-run"

    log_debug "Creating wrapper script: $wrapper_path"

    cat > "$wrapper_path" << EOF
#!/bin/bash
# s01 $component wrapper script
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
        echo -e "  ${GREEN}✓${NC} s01 $component"
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
        echo -e "  ${INSTALL_PREFIX}/bin/s01-server-run"
        echo -e "  # Or with custom config:"
        echo -e "  ${INSTALL_PREFIX}/bin/s01-server --help"
        echo
    fi

    if [[ " ${installed_components[*]} " =~ " client " ]]; then
        echo -e "${CYAN}Client:${NC}"
        echo -e "  # Start client (configure SERVER_URL in config first)"
        echo -e "  ${INSTALL_PREFIX}/bin/s01-client-run"
        echo -e "  # Or with custom config:"
        echo -e "  ${INSTALL_PREFIX}/bin/s01-client --help"
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
        --diagnose)
            diagnose_system
            exit 0
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

    log_info "Installing s01"
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
        echo
        log_info "=== Installing Server ==="
        local server_binary
        if server_binary=$(download_with_fallback "server" "$VERSION" "$arch" "$temp_dir"); then
            install_binary "$server_binary" "server" "$bin_dir"
            create_config "server"
            create_wrapper "server" "$bin_dir"
            installed_components+=("server")
        else
            echo
            log_error "Server installation failed"
            log_error "Run with --diagnose for troubleshooting information"
            exit 1
        fi
    fi

    # Download and install client
    if [[ "$INSTALL_CLIENT" == "true" ]]; then
        echo
        log_info "=== Installing Client ==="
        local client_binary
        if client_binary=$(download_with_fallback "client" "$VERSION" "$arch" "$temp_dir"); then
            install_binary "$client_binary" "client" "$bin_dir"
            create_config "client"
            create_wrapper "client" "$bin_dir"
            installed_components+=("client")
        else
            echo
            log_error "Client installation failed"
            log_error "Run with --diagnose for troubleshooting information"
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
