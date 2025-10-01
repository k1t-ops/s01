#!/bin/bash
set -euo pipefail

# s01 - Cross-Platform Installation Script
# Usage: curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/YOUR_REPO/main/install.sh | bash
# Or:    wget -qO- https://raw.githubusercontent.com/YOUR_ORG/YOUR_REPO/main/install.sh | bash

# Configuration
GITHUB_REPO="${S01_REPO:-k1t-ops/s01}"
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
    echo "│                   S01 Installer                     │"
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
    echo -e "${BLUE}[DEBUG]${NC} $1" >&2
}

# Usage information
usage() {
    cat << EOF
${GREEN}S01 Installer${NC}

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
  S01_REPO              Override GitHub repository
  GITHUB_TOKEN          GitHub token for private repositories

${YELLOW}SUPPORTED PLATFORMS:${NC}
  Linux:  amd64, arm64, armv7
  macOS:  amd64 (Intel), arm64 (Apple Silicon)

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

        # Platform-specific installation hints
        if [[ "$DETECTED_OS" == "darwin" ]]; then
            log_info "On macOS, you can use Homebrew:"
            log_info "  brew install ${missing_deps[*]}"
        elif command -v apt-get >/dev/null 2>&1; then
            log_info "On Debian/Ubuntu:"
            log_info "  sudo apt-get install ${missing_deps[*]}"
        elif command -v yum >/dev/null 2>&1; then
            log_info "On RHEL/CentOS:"
            log_info "  sudo yum install ${missing_deps[*]}"
        fi

        exit 1
    fi
}

# Detect operating system
detect_os() {
    local raw_os
    raw_os="$(uname -s 2>/dev/null)"

    if [[ -z "$raw_os" ]]; then
        log_error "Cannot detect operating system"
        exit 1
    fi

    local normalized_os
    case "$raw_os" in
        Linux|linux)
            normalized_os="linux"
            ;;
        Darwin|darwin)
            normalized_os="darwin"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            log_error "Windows is not directly supported"
            log_error "Please use WSL (Windows Subsystem for Linux) or Docker"
            exit 1
            ;;
        *)
            log_error "Unsupported operating system: $raw_os"
            log_error "Supported systems: Linux, macOS"
            exit 1
            ;;
    esac

    log_debug "Detected OS: $raw_os → $normalized_os"
    DETECTED_OS="$normalized_os"
    return 0
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
            if [[ "$DETECTED_OS" == "darwin" ]]; then
                log_error "macOS does not support ARMv7 architecture"
                exit 1
            fi
            normalized_arch="armv7"
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
            if [[ "$DETECTED_OS" == "linux" ]]; then
                log_error "  • x86_64 (Intel/AMD 64-bit) → amd64 binaries"
                log_error "  • aarch64 (ARM 64-bit) → arm64 binaries"
                log_error "  • armv7l (ARM 32-bit) → armv7 binaries"
            else
                log_error "  • x86_64 (Intel 64-bit) → amd64 binaries"
                log_error "  • arm64 (Apple Silicon) → arm64 binaries"
            fi
            echo
            log_error "If you believe this architecture should be supported,"
            log_error "please open an issue at: https://github.com/$GITHUB_REPO/issues"
            exit 1
            ;;
    esac

    log_debug "Detected architecture: $raw_arch → $normalized_arch"
    DETECTED_ARCH="$normalized_arch"
    return 0
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
    version=$(echo "$api_response" | grep '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)

    if [[ -z "$version" || "$version" == "null" ]]; then
        log_error "No releases found for repository: $GITHUB_REPO"
        echo
        log_error "The repository exists but has no published releases."
        log_error "Please ask the maintainer to create a release with binaries."
        log_error "Releases page: https://github.com/$GITHUB_REPO/releases"

        exit 1
    fi

    LATEST_VERSION="$version"
    return 0
}

# Download and extract binary
download_binary() {
    local component="$1"
    local version="$2"
    local os="$3"
    local arch="$4"
    local temp_dir="$5"

    # Adjust architecture naming for compatibility
    local arch_name="$arch"
    if [[ "$arch" == "armv7" && "$os" == "linux" ]]; then
        arch_name="armv7"
    fi

    local binary_name="s01-${component}-${os}-${arch_name}"
    local download_url="https://github.com/$GITHUB_REPO/releases/download/$version/${binary_name}.tar.gz"

    log_info "Downloading $component binary..."
    log_debug "  Version: $version"
    log_debug "  OS: $os"
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
        200|302)
            log_debug "Download URL is accessible"
            ;;
        404)
            log_error "Binary not found: $binary_name.tar.gz"
            log_error "Available files: https://github.com/$GITHUB_REPO/releases/tag/$version"
            return 1
            ;;
        403)
            log_error "Access denied to repository: $GITHUB_REPO"
            log_error "Set GITHUB_TOKEN environment variable for private repositories"
            return 1
            ;;
        *)
            log_error "Cannot access release (HTTP $http_code)"
            log_error "URL: $download_url"
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
    DOWNLOADED_BINARY="$binary_file"
    return 0
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

    if [[ "$DETECTED_OS" == "darwin" ]]; then
        echo "  macOS Version: $(sw_vers -productVersion 2>/dev/null || echo 'Unknown')"
    fi
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

    echo "Platform Detection:"
    local raw_os=$(uname -s 2>/dev/null || echo "unknown")
    local raw_arch=$(uname -m 2>/dev/null || echo "unknown")
    echo "  Raw OS: $raw_os"
    echo "  Raw Architecture: $raw_arch"

    # Detect normalized values
    detect_os
    detect_arch

    echo "  Normalized OS: $DETECTED_OS"
    echo "  Normalized Architecture: $DETECTED_ARCH"
    echo "  Binary Pattern: s01-*-${DETECTED_OS}-${DETECTED_ARCH}.tar.gz"
    echo

    echo "Available Tools:"
    for tool in curl tar wget; do
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
    local os="$3"
    local primary_arch="$4"
    local temp_dir="$5"

    # Try primary architecture first
    if download_binary "$component" "$version" "$os" "$primary_arch" "$temp_dir"; then
        FALLBACK_BINARY="$DOWNLOADED_BINARY"
        return 0
    fi

    log_warn "$component binary not available for $os-$primary_arch"

    # Define fallback architectures based on OS and primary arch
    local fallback_archs=()

    if [[ "$os" == "darwin" ]]; then
        # macOS Rosetta 2 can run Intel binaries on Apple Silicon
        case "$primary_arch" in
            arm64)
                fallback_archs=("amd64")
                log_info "Trying fallback: ARM64 → AMD64 (will use Rosetta 2 emulation)"
                ;;
            amd64)
                # Intel Macs cannot run ARM64 binaries
                ;;
        esac
    elif [[ "$os" == "linux" ]]; then
        case "$primary_arch" in
            arm64|armv7)
                # ARM Linux might work with QEMU emulation
                fallback_archs=("amd64")
                log_info "Trying fallback: ARM → AMD64 (may work with QEMU emulation)"
                ;;
            amd64)
                # No fallbacks for amd64 as it's the most common
                ;;
        esac
    fi

    # Try fallback architectures
    if [ ${#fallback_archs[@]} -gt 0 ]; then
        for fallback_arch in "${fallback_archs[@]}"; do
            log_info "Attempting download with $fallback_arch architecture..."
            if download_binary "$component" "$version" "$os" "$fallback_arch" "$temp_dir"; then
                log_warn "Using $fallback_arch binary instead of $primary_arch"
                if [[ "$os" == "darwin" && "$primary_arch" == "arm64" && "$fallback_arch" == "amd64" ]]; then
                    log_warn "This Intel binary will run under Rosetta 2 emulation"
                    log_warn "Performance may be reduced compared to native ARM64 binary"
                else
                    log_warn "This may work but is not optimal for your system"
                fi
                FALLBACK_BINARY="$DOWNLOADED_BINARY"
                return 0
            fi
        done
    fi

    log_error "No compatible binary found for any architecture"
    echo
    local tried_archs="$primary_arch${fallback_archs:+ ${fallback_archs[*]}}"
    log_error "Tried architectures: $tried_archs"
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

    # Check if install directory exists
    if [[ ! -d "$install_dir" ]]; then
        log_info "Creating install directory: $install_dir"
        if ! sudo mkdir -p "$install_dir" 2>/dev/null; then
            log_error "Cannot create install directory: $install_dir"
            log_error "Please create it manually with appropriate permissions"
            return 1
        fi
    fi

    # Copy binary
    if ! sudo cp "$binary_path" "$target_path" 2>/dev/null; then
        log_error "Cannot copy binary to $target_path (permission denied)"
        log_info "Please run with elevated privileges:"
        log_info "  sudo cp $binary_path $target_path"
        return 1
    fi

    # Make executable
    if ! sudo chmod +x "$target_path" 2>/dev/null; then
        log_error "Cannot make binary executable: $target_path (permission denied)"
        log_info "Please run:"
        log_info "  sudo chmod +x $target_path"
        return 1
    fi

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

    # Create config directory if it doesn't exist
    if [[ ! -d "$CONFIG_DIR" ]]; then
        log_info "Creating config directory: $CONFIG_DIR"
        if ! mkdir -p "$CONFIG_DIR" 2>/dev/null; then
            log_error "Cannot create config directory: $CONFIG_DIR"
            log_error "Please create it manually:"
            log_error "  mkdir -p $CONFIG_DIR"
            return 1
        fi
    fi

    local config_file="$CONFIG_DIR/${component}.env"

    if [[ -f "$config_file" ]]; then
        log_info "Configuration already exists: $config_file"
        return 0
    fi

    log_info "Creating basic configuration for $component..."

    if [[ "$component" == "server" ]]; then
        if ! cat > "$config_file" 2>/dev/null << EOF
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
        then
            log_error "Cannot write config file: $config_file (permission denied)"
            log_info "Please run with elevated privileges or use a different config directory"
            return 1
        fi
    elif [[ "$component" == "client" ]]; then
        if ! cat > "$config_file" 2>/dev/null << EOF
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
        then
            log_error "Cannot write config file: $config_file (permission denied)"
            log_info "Please run with elevated privileges or use a different config directory"
            return 1
        fi
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

    if ! sudo cat > "$wrapper_path" 2>/dev/null << EOF
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
    then
        log_error "Cannot create wrapper script: $wrapper_path (permission denied)"
        log_info "Please run with elevated privileges or use a different install directory"
        return 1
    fi

    sudo chmod +x "$wrapper_path"
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
    echo -e "  Platform: $DETECTED_OS ($DETECTED_ARCH)"
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
        if [[ "$DETECTED_OS" == "linux" ]]; then
            echo -e "  ${BLUE}4.${NC} Consider creating systemd services for automatic startup"
        elif [[ "$DETECTED_OS" == "darwin" ]]; then
            echo -e "  ${BLUE}4.${NC} Consider creating launchd plist files for automatic startup"
        fi
    fi

    echo
    echo -e "${GREEN}For more information:${NC}"
    echo -e "  Repository: https://github.com/$GITHUB_REPO"
    echo -e "  Documentation: https://github.com/$GITHUB_REPO#readme"
    echo

    # Platform-specific tips
    if [[ "$DETECTED_OS" == "darwin" && "$DETECTED_ARCH" == "arm64" ]]; then
        echo -e "${CYAN}Apple Silicon Note:${NC}"
        echo -e "  You're running on Apple Silicon (M1/M2/M3)"
        echo -e "  The installed binaries are native ARM64"
        echo
    elif [[ "$DETECTED_OS" == "darwin" && "$DETECTED_ARCH" == "amd64" ]]; then
        echo -e "${CYAN}Intel Mac Note:${NC}"
        echo -e "  You're running on an Intel-based Mac"
        echo -e "  The installed binaries are native x86_64"
        echo
    fi
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
            if [[ "$(uname -s)" == "Linux" ]]; then
                CONFIG_DIR="/etc/s01"
            else
                CONFIG_DIR="/usr/local/etc/s01"
            fi
            SERVICE_USER="root"
            shift
            ;;
        --diagnose)
            # Detect OS and architecture first for diagnostics
            detect_os
            detect_arch
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

    # Detect OS and architecture first
    detect_os
    if [[ -z "$DETECTED_OS" ]]; then
        log_error "Failed to detect operating system"
        exit 1
    fi

    detect_arch
    if [[ -z "$DETECTED_ARCH" ]]; then
        log_error "Failed to detect system architecture"
        exit 1
    fi

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
    log_info "Platform: $DETECTED_OS ($DETECTED_ARCH)"
    log_info "Install prefix: $INSTALL_PREFIX"

    # Check dependencies
    check_dependencies

    local os="$DETECTED_OS"
    local arch="$DETECTED_ARCH"
    log_info "Detected platform: $os-$arch"

    # Get version
    if [[ "$VERSION" == "latest" ]]; then
        log_info "Resolving latest version..."
        get_latest_version
        if [[ -z "$LATEST_VERSION" ]]; then
            log_error "Failed to resolve latest version"
            log_error "Please specify a version with --version or check repository releases"
            exit 1
        fi
        VERSION="$LATEST_VERSION"
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

    local installed_components=()

    # Download and install server
    if [[ "$INSTALL_SERVER" == "true" ]]; then
        echo
        log_info "=== Installing Server ==="
        if download_with_fallback "server" "$VERSION" "$os" "$arch" "$temp_dir"; then
            install_binary "$FALLBACK_BINARY" "server" "$bin_dir"
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
        if download_with_fallback "client" "$VERSION" "$os" "$arch" "$temp_dir"; then
            install_binary "$FALLBACK_BINARY" "client" "$bin_dir"
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
        if [[ "$DETECTED_OS" == "darwin" ]]; then
            # macOS: prefer .zprofile for zsh (default on modern macOS)
            if [[ "$SHELL" == */zsh ]]; then
                shell_config="$HOME/.zprofile"
            elif [[ "$SHELL" == */bash ]]; then
                shell_config="$HOME/.bash_profile"
            fi
        else
            # Linux
            if [[ -f "$HOME/.bashrc" ]]; then
                shell_config="$HOME/.bashrc"
            elif [[ -f "$HOME/.zshrc" ]]; then
                shell_config="$HOME/.zshrc"
            elif [[ -f "$HOME/.profile" ]]; then
                shell_config="$HOME/.profile"
            fi
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

# Run main function (arguments already parsed globally)
main
