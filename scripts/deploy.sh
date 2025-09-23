#!/bin/bash
set -euo pipefail

# Simple deployment wrapper for Host S01 Service
# This script provides easy commands for common deployment scenarios

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="$SCRIPT_DIR/deploy-binary.sh"

# Configuration
DEFAULT_REPO="${S01_REPO:-your-org/s01-service}"  # Set S01_REPO env var or update this default
VERSION="latest"
ENVIRONMENT=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

usage() {
    cat << EOF
Usage: $0 <command> [options]

Simple deployment wrapper for Host S01 Service

COMMANDS:
    server                  Deploy s01 server only
    client                  Deploy s01 client only
    full                    Deploy both server and client
    production             Deploy for production environment
    development            Deploy for development environment
    update                 Update existing installation
    status                 Check deployment status
    logs                   View service logs
    start                  Start services
    stop                   Stop services
    restart                Restart services
    remove                 Remove installation

OPTIONS:
    --repo REPO            GitHub repository (default: $DEFAULT_REPO)
    --version VERSION      Version to deploy (default: $VERSION)
    --force                Force overwrite existing installation
    --dry-run              Show what would be done
    --help                 Show detailed help

EXAMPLES:
    $0 server                           # Deploy server only
    $0 client --version v1.2.3          # Deploy specific client version
    $0 full --repo myorg/repo           # Deploy both from custom repo
    $0 production                       # Production deployment
    $0 update                           # Update to latest version
    $0 status                           # Check service status

ENVIRONMENT VARIABLES:
    S01_REPO     GitHub repository (overrides default)
    GITHUB_TOKEN       GitHub token for private repositories

EOF
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root for system deployment"
        echo "Try: sudo $0 $*"
        exit 1
    fi
}

check_deploy_script() {
    if [[ ! -f "$DEPLOY_SCRIPT" ]]; then
        log_error "Deploy script not found: $DEPLOY_SCRIPT"
        exit 1
    fi

    if [[ ! -x "$DEPLOY_SCRIPT" ]]; then
        chmod +x "$DEPLOY_SCRIPT"
    fi
}

parse_options() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --repo)
                DEFAULT_REPO="$2"
                shift 2
                ;;
            --version)
                VERSION="$2"
                shift 2
                ;;
            --force|--dry-run|--help)
                # Pass these through to the main script
                EXTRA_ARGS="$EXTRA_ARGS $1"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

deploy_server() {
    log_info "Deploying s01 server..."
    "$DEPLOY_SCRIPT" --server --repo "$DEFAULT_REPO" --version "$VERSION" $EXTRA_ARGS
}

deploy_client() {
    log_info "Deploying s01 client..."
    "$DEPLOY_SCRIPT" --client --repo "$DEFAULT_REPO" --version "$VERSION" $EXTRA_ARGS
}

deploy_full() {
    log_info "Deploying full s01 service (server + client)..."
    "$DEPLOY_SCRIPT" --all --repo "$DEFAULT_REPO" --version "$VERSION" $EXTRA_ARGS
}

deploy_production() {
    log_info "Deploying for production environment..."

    # Production-specific settings
    local prod_args="--all --repo $DEFAULT_REPO --version $VERSION"
    prod_args="$prod_args --install-dir /opt/s01"
    prod_args="$prod_args --config-dir /etc/s01"
    prod_args="$prod_args --cert-dir /etc/ssl/s01"
    prod_args="$prod_args --data-dir /var/lib/s01"
    prod_args="$prod_args --log-dir /var/log/s01"
    prod_args="$prod_args --user s01 --group s01"

    "$DEPLOY_SCRIPT" $prod_args $EXTRA_ARGS

    log_info "Production deployment completed"
    log_warn "Remember to:"
    log_warn "1. Install proper SSL certificates"
    log_warn "2. Configure firewall rules"
    log_warn "3. Set up log rotation"
    log_warn "4. Configure monitoring"
}

deploy_development() {
    log_info "Deploying for development environment..."

    # Development-specific settings
    local dev_args="--all --repo $DEFAULT_REPO --version $VERSION"
    dev_args="$dev_args --install-dir /usr/local/bin"
    dev_args="$dev_args --config-dir /usr/local/etc/s01"
    dev_args="$dev_args --cert-dir /usr/local/etc/ssl/s01"
    dev_args="$dev_args --data-dir /usr/local/var/s01"
    dev_args="$dev_args --log-dir /usr/local/var/log/s01"
    dev_args="$dev_args --user $USER --group $(id -gn)"
    dev_args="$dev_args --no-systemd"

    "$DEPLOY_SCRIPT" $dev_args $EXTRA_ARGS

    log_info "Development deployment completed"
    log_info "Services are installed but not configured for systemd"
    log_info "Run binaries manually or create your own service scripts"
}

update_installation() {
    log_info "Updating existing installation..."

    # Check what's currently installed
    local has_server=false
    local has_client=false

    if [[ -f "/opt/s01/s01-server" ]] || [[ -f "/usr/local/bin/s01-server" ]]; then
        has_server=true
    fi

    if [[ -f "/opt/s01/s01-client" ]] || [[ -f "/usr/local/bin/s01-client" ]]; then
        has_client=true
    fi

    if [[ "$has_server" == false && "$has_client" == false ]]; then
        log_error "No existing installation found"
        log_info "Use 'deploy.sh server', 'deploy.sh client', or 'deploy.sh full' for initial installation"
        exit 1
    fi

    # Update what's installed
    local update_args="--force --repo $DEFAULT_REPO --version $VERSION"

    if [[ "$has_server" == true && "$has_client" == true ]]; then
        update_args="$update_args --all"
    elif [[ "$has_server" == true ]]; then
        update_args="$update_args --server"
    elif [[ "$has_client" == true ]]; then
        update_args="$update_args --client"
    fi

    "$DEPLOY_SCRIPT" $update_args $EXTRA_ARGS

    log_info "Update completed - restart services to use new version"
}

show_status() {
    log_info "S01 Service Status:"
    echo

    # Check if binaries exist
    echo "Installation Status:"
    for binary in "/opt/s01/s01-server" "/usr/local/bin/s01-server"; do
        if [[ -f "$binary" ]]; then
            echo "  Server: $binary ($(stat -c %y "$binary"))"
            break
        fi
    done

    for binary in "/opt/s01/s01-client" "/usr/local/bin/s01-client"; do
        if [[ -f "$binary" ]]; then
            echo "  Client: $binary ($(stat -c %y "$binary"))"
            break
        fi
    done

    echo

    # Check systemd services
    if command -v systemctl &> /dev/null; then
        echo "Service Status:"
        for service in "s01-server" "s01-client"; do
            if systemctl list-unit-files | grep -q "$service.service"; then
                local status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
                local enabled=$(systemctl is-enabled "$service" 2>/dev/null || echo "disabled")
                echo "  $service: $status ($enabled)"
            fi
        done
    fi

    echo

    # Check processes
    echo "Running Processes:"
    if pgrep -f s01-server >/dev/null; then
        echo "  s01-server: $(pgrep -f s01-server | wc -l) process(es)"
    else
        echo "  s01-server: not running"
    fi

    if pgrep -f s01-client >/dev/null; then
        echo "  s01-client: $(pgrep -f s01-client | wc -l) process(es)"
    else
        echo "  s01-client: not running"
    fi
}

show_logs() {
    if command -v systemctl &> /dev/null; then
        log_info "Showing service logs (press Ctrl+C to exit)..."
        journalctl -u s01-server -u s01-client -f
    else
        log_info "Checking log files..."
        for log_dir in "/var/log/s01" "/usr/local/var/log/s01"; do
            if [[ -d "$log_dir" ]]; then
                echo "Log directory: $log_dir"
                ls -la "$log_dir"
                echo
                for log_file in "$log_dir"/*.log; do
                    if [[ -f "$log_file" ]]; then
                        echo "=== $(basename "$log_file") ==="
                        tail -20 "$log_file"
                        echo
                    fi
                done
            fi
        done
    fi
}

start_services() {
    log_info "Starting s01 services..."

    if command -v systemctl &> /dev/null; then
        for service in "s01-server" "s01-client"; do
            if systemctl list-unit-files | grep -q "$service.service"; then
                systemctl start "$service" || log_warn "Failed to start $service"
            fi
        done
        sleep 2
        show_status
    else
        log_warn "systemd not available - please start services manually"
        log_info "Server binary locations:"
        find /opt /usr/local -name "s01-*" -type f 2>/dev/null || true
    fi
}

stop_services() {
    log_info "Stopping s01 services..."

    if command -v systemctl &> /dev/null; then
        for service in "s01-server" "s01-client"; do
            if systemctl list-unit-files | grep -q "$service.service"; then
                systemctl stop "$service" || log_warn "Failed to stop $service"
            fi
        done
    fi

    # Also kill any running processes
    pkill -f s01-server || true
    pkill -f s01-client || true

    log_info "Services stopped"
}

restart_services() {
    stop_services
    sleep 2
    start_services
}

remove_installation() {
    log_warn "This will completely remove the S01 Service installation"
    read -p "Are you sure? [y/N] " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Removal cancelled"
        exit 0
    fi

    log_info "Removing S01 Service installation..."

    # Stop services
    stop_services

    # Remove systemd services
    if command -v systemctl &> /dev/null; then
        for service in "s01-server" "s01-client"; do
            if systemctl list-unit-files | grep -q "$service.service"; then
                systemctl disable "$service" || true
                rm -f "/etc/systemd/system/$service.service"
            fi
        done
        systemctl daemon-reload
    fi

    # Remove files and directories
    rm -rf /opt/s01
    rm -rf /etc/s01
    rm -rf /var/lib/s01
    rm -rf /var/log/s01
    rm -rf /usr/local/bin/s01-*
    rm -rf /usr/local/etc/s01
    rm -rf /usr/local/var/s01
    rm -rf /usr/local/var/log/s01

    # Remove user (be careful here)
    if getent passwd s01 >/dev/null 2>&1; then
        userdel s01 || log_warn "Could not remove user 's01'"
    fi

    if getent group s01 >/dev/null 2>&1; then
        groupdel s01 || log_warn "Could not remove group 's01'"
    fi

    log_info "S01 Service removed completely"
}

# Main script
COMMAND="${1:-}"
EXTRA_ARGS=""

if [[ -z "$COMMAND" ]]; then
    log_error "No command specified"
    usage
    exit 1
fi

# Parse remaining arguments
shift
parse_options "$@"

# Check prerequisites
check_deploy_script

case "$COMMAND" in
    server)
        check_root
        deploy_server
        ;;
    client)
        check_root
        deploy_client
        ;;
    full)
        check_root
        deploy_full
        ;;
    production)
        check_root
        deploy_production
        ;;
    development)
        deploy_development
        ;;
    update)
        check_root
        update_installation
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    start)
        check_root
        start_services
        ;;
    stop)
        check_root
        stop_services
        ;;
    restart)
        check_root
        restart_services
        ;;
    remove)
        check_root
        remove_installation
        ;;
    --help|-h|help)
        usage
        echo
        echo "For detailed options, use: $DEPLOY_SCRIPT --help"
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac
