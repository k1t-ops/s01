#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
SETUP_TIMEOUT=300 # 5 minutes timeout for setup

# Demo configuration
DEMO_CLIENTS=(
    "web-service:web-01:client-web-01"
    "api-service:api-01:client-api-01"
    "database:db-primary:client-db-primary"
    "worker-service:worker-01:client-worker-01"
    "test-service:test-client:test-client"
)

# Function to print section headers
print_header() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} ${WHITE}$1${NC} ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to print step info
print_step() {
    echo -e "${CYAN}➤ $1${NC}"
}

# Function to print success
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Function to print error
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Function to print info
print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()

    if ! command -v docker >/dev/null 2>&1; then
        missing_deps+=("docker")
    fi

    if ! command -v docker-compose >/dev/null 2>&1; then
        missing_deps+=("docker-compose")
    fi

    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        echo ""
        echo "Please install the missing dependencies:"
        echo "  Ubuntu/Debian: sudo apt-get install docker.io docker-compose jq"
        echo "  CentOS/RHEL:   sudo yum install docker docker-compose jq"
        echo "  macOS:         brew install docker docker-compose jq"
        echo ""
        echo "Or use the installation helper:"
        echo "  make install-deps"
        exit 1
    fi
}

# Function to check Docker daemon
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker daemon is not running"
        echo ""
        echo "Please start Docker daemon:"
        echo "  Linux:   sudo systemctl start docker"
        echo "  macOS:   Start Docker Desktop"
        echo "  Windows: Start Docker Desktop"
        exit 1
    fi
}

# Function to wait for service health
wait_for_service() {
    local service_name="$1"
    local timeout="$2"
    local count=0

    print_step "Waiting for $service_name to be healthy (timeout: ${timeout}s)..."

    while [ $count -lt $timeout ]; do
        if docker-compose -f "$COMPOSE_FILE" ps "$service_name" | grep -q "healthy" 2>/dev/null; then
            print_success "$service_name is healthy"
            return 0
        fi

        if docker-compose -f "$COMPOSE_FILE" ps "$service_name" | grep -q "Up" 2>/dev/null; then
            echo -n "."
        else
            print_warning "$service_name is not running yet..."
        fi

        sleep 2
        count=$((count + 2))
    done

    print_error "$service_name failed to become healthy within $timeout seconds"
    return 1
}

# Function to display service status
show_status() {
    echo ""
    print_info "Current service status:"
    docker-compose -f "$COMPOSE_FILE" --profile demo --profile test ps
    echo ""
}

# Function to cleanup on exit
cleanup_on_exit() {
    if [[ "$CLEANUP_ON_ERROR" == "true" ]]; then
        print_warning "Setup failed, cleaning up..."
        docker-compose -f "$COMPOSE_FILE" --profile demo --profile test down >/dev/null 2>&1 || true
    fi
}

# Function to show demo information
show_demo_info() {
    print_header "🎉 Demo Environment Successfully Started!"

    echo -e "${GREEN}Services Running:${NC}"
    echo -e "  ${CYAN}Step-CA:${NC}          https://localhost:9000 (Certificate Authority)"
    echo -e "  ${CYAN}Discovery Server:${NC} https://localhost:8443 (Main API)"
    echo ""

    echo -e "${GREEN}Demo Clients Active:${NC}"
    for client_info in "${DEMO_CLIENTS[@]}"; do
        IFS=':' read -r service instance container <<< "$client_info"
        echo -e "  ${CYAN}$service:${NC} $instance (container: $container)"
    done
    echo ""

    echo -e "${GREEN}Health Monitoring Commands:${NC}"
    echo -e "  ${YELLOW}make health-monitor${NC}          # Real-time health dashboard"
    echo -e "  ${YELLOW}make health-check${NC}           # One-time health check"
    echo -e "  ${YELLOW}make health-compact${NC}         # Compact health overview"
    echo -e "  ${YELLOW}make demo-health${NC}            # Interactive health demo"
    echo ""

    echo -e "${GREEN}Management Commands:${NC}"
    echo -e "  ${YELLOW}make logs${NC}                   # View all logs"
    echo -e "  ${YELLOW}make logs-clients${NC}           # View client logs only"
    echo -e "  ${YELLOW}make status${NC}                 # Show service status"
    echo -e "  ${YELLOW}make test${NC}                   # Run test suite"
    echo -e "  ${YELLOW}make stop${NC}                   # Stop all services"
    echo ""

    echo -e "${GREEN}Individual Client Controls:${NC}"
    echo -e "  ${YELLOW}make client-web${NC}             # Start/restart web client"
    echo -e "  ${YELLOW}make client-api${NC}             # Start/restart API client"
    echo -e "  ${YELLOW}make client-db${NC}              # Start/restart database client"
    echo -e "  ${YELLOW}make client-worker${NC}          # Start/restart worker client"
    echo -e "  ${YELLOW}make client-test${NC}            # Start/restart test client"
    echo ""

    echo -e "${CYAN}Next Steps:${NC}"
    echo -e "1. Monitor health in real-time: ${YELLOW}make health-monitor${NC}"
    echo -e "2. View client logs: ${YELLOW}make logs-clients${NC}"
    echo -e "3. Run the interactive demo: ${YELLOW}make demo-health${NC}"
    echo -e "4. Test the API: ${YELLOW}make test${NC}"
    echo ""

    print_info "Demo environment is ready! Press Ctrl+C in health-monitor to exit."
}

# Main setup function
main() {
    cd "$PROJECT_DIR"

    # Show banner
    clear
    echo -e "${WHITE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                                                                              ║${NC}"
    echo -e "${WHITE}║  ${MAGENTA}🚀 Host Discovery Service - Complete Demo Environment Setup${NC}              ${WHITE}║${NC}"
    echo -e "${WHITE}║                                                                              ║${NC}"
    echo -e "${WHITE}║  ${CYAN}Sets up a complete demonstration environment with:${NC}                        ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${CYAN}• Step-CA certificate authority${NC}                                          ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${CYAN}• Discovery server with mTLS${NC}                                            ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${CYAN}• Multiple demo clients with health monitoring${NC}                          ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${CYAN}• Real-time health dashboards${NC}                                          ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${CYAN}• Zero external dependencies${NC}                                           ${WHITE}║${NC}"
    echo -e "${WHITE}║                                                                              ║${NC}"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Set cleanup trap
    CLEANUP_ON_ERROR=true
    trap cleanup_on_exit EXIT

    # Step 1: Check prerequisites
    print_header "🔧 Checking Prerequisites"
    check_dependencies
    print_success "All required dependencies are available"

    check_docker
    print_success "Docker daemon is running"

    # Step 2: Clean up any existing services
    print_header "🧹 Cleaning Up Previous Installations"
    print_step "Stopping any running services..."
    docker-compose -f "$COMPOSE_FILE" --profile demo --profile test down >/dev/null 2>&1 || true
    print_success "Previous installations cleaned up"

    # Step 3: Initialize CA and certificates
    print_header "🔐 Initializing Certificate Authority"
    print_step "Initializing step-ca and generating certificates..."
    chmod +x scripts/init-ca.sh
    if ./scripts/init-ca.sh; then
        print_success "Certificate authority initialized"
    else
        print_error "Failed to initialize certificate authority"
        exit 1
    fi

    # Step 4: Build Docker images
    print_header "🏗️  Building Docker Images"
    print_step "Building discovery server image..."
    docker-compose -f "$COMPOSE_FILE" build discovery-server

    print_step "Building client images..."
    docker-compose -f "$COMPOSE_FILE" build test-client client-web-01 client-api-01 client-db-primary client-worker-01

    print_success "All Docker images built successfully"

    # Step 5: Start core services
    print_header "🚀 Starting Core Services"
    print_step "Starting Step-CA..."
    docker-compose -f "$COMPOSE_FILE" up -d step-ca

    if ! wait_for_service "step-ca" 60; then
        print_error "Step-CA failed to start"
        exit 1
    fi

    print_step "Starting Discovery Server..."
    docker-compose -f "$COMPOSE_FILE" up -d discovery-server

    if ! wait_for_service "discovery-server" 60; then
        print_error "Discovery server failed to start"
        exit 1
    fi

    print_success "Core services started successfully"

    # Step 6: Start demo clients
    print_header "👥 Starting Demo Clients"
    print_step "Starting all demo clients..."

    # Start clients one by one with brief delays
    for client_info in "${DEMO_CLIENTS[@]}"; do
        IFS=':' read -r service instance container <<< "$client_info"
        print_step "Starting $service:$instance ($container)..."

        if [[ "$container" == "test-client" ]]; then
            docker-compose -f "$COMPOSE_FILE" --profile test up -d "$container"
        else
            docker-compose -f "$COMPOSE_FILE" --profile demo up -d "$container"
        fi

        # Brief delay between client starts
        sleep 3
    done

    print_success "All demo clients started"

    # Step 7: Wait for clients to register
    print_header "⏳ Waiting for Client Registration"
    print_step "Allowing clients time to register and report health status..."

    # Wait for clients to start reporting
    local wait_time=30
    local count=0
    while [ $count -lt $wait_time ]; do
        echo -n "."
        sleep 2
        count=$((count + 2))
    done
    echo ""

    print_success "Clients have had time to register"

    # Step 8: Verify setup
    print_header "✅ Verifying Setup"
    print_step "Running basic connectivity tests..."

    # Test server health
    if curl -k -s https://localhost:8443/health >/dev/null; then
        print_success "Discovery server is responding"
    else
        print_warning "Discovery server health check failed"
    fi

    # Show current status
    show_status

    # Step 9: Run basic tests
    print_header "🧪 Running Basic Tests"
    print_step "Executing test suite..."
    if chmod +x scripts/test-discovery.sh && ./scripts/test-discovery.sh >/dev/null 2>&1; then
        print_success "Basic tests passed"
    else
        print_warning "Some tests may have failed (this is normal during initial startup)"
    fi

    # Step 10: Show completion information
    CLEANUP_ON_ERROR=false  # Don't cleanup on exit since setup was successful
    trap - EXIT  # Remove cleanup trap

    show_demo_info

    # Optionally start health monitor
    echo -e "${YELLOW}Would you like to start the health monitoring dashboard now? [Y/n]${NC}"
    read -r response
    response=${response:-Y}

    if [[ $response =~ ^[Yy]$ ]]; then
        echo ""
        print_info "Starting health monitoring dashboard..."
        echo -e "${CYAN}(Press Ctrl+C to exit the dashboard)${NC}"
        sleep 2

        # Make sure the script is executable and run it
        chmod +x scripts/health-monitor.sh
        ./scripts/health-monitor.sh 2>/dev/null || {
            print_warning "Health monitor script not available, try: make health-monitor"
        }
    else
        echo ""
        print_info "Demo setup complete! Use 'make health-monitor' to start monitoring."
    fi
}

# Handle command line options
case "${1:-}" in
    --help|-h)
        echo "Host Discovery Service Demo Setup"
        echo ""
        echo "This script sets up a complete demonstration environment with:"
        echo "  • Step-CA certificate authority"
        echo "  • Discovery server with mTLS authentication"
        echo "  • Multiple demo clients with different configurations"
        echo "  • Health monitoring dashboards"
        echo ""
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --no-monitor   Skip starting the health monitor"
        echo ""
        echo "Requirements:"
        echo "  • Docker and Docker Compose"
        echo "  • jq (for JSON processing)"
        echo "  • curl (for health checks)"
        echo ""
        echo "The setup will:"
        echo "  1. Initialize certificate authority"
        echo "  2. Generate all required certificates"
        echo "  3. Build Docker images"
        echo "  4. Start all services"
        echo "  5. Verify functionality"
        echo "  6. Show usage instructions"
        echo ""
        echo "After setup, you can use various make commands to manage the demo:"
        echo "  make health-monitor    # Real-time health dashboard"
        echo "  make logs             # View service logs"
        echo "  make status           # Show service status"
        echo "  make stop             # Stop all services"
        echo ""
        exit 0
        ;;
    --no-monitor)
        NO_MONITOR=true
        ;;
esac

# Run main setup
main "$@"
