#!/bin/bash
set -euo pipefail

# Configuration script for S01 Service deployment
# This script helps set up repository settings for binary deployment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

print_header() {
    echo "======================================================"
    echo "        S01 Service - Deployment Configuration        "
    echo "======================================================"
    echo
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Configure deployment settings for S01 Service

OPTIONS:
    --repo REPO         Set GitHub repository (e.g., myorg/discovery-service)
    --check             Check current configuration
    --reset             Reset to default configuration
    --interactive       Interactive configuration (default)
    --env-file          Create environment file instead of updating scripts
    --help              Show this help message

EXAMPLES:
    $0                                  # Interactive configuration
    $0 --repo myorg/discovery-service   # Set repository directly
    $0 --check                          # Show current settings
    $0 --env-file                       # Create .env file for configuration

EOF
}

get_current_config() {
    local deploy_script="$SCRIPT_DIR/deploy-binary.sh"
    local wrapper_script="$SCRIPT_DIR/deploy.sh"

    if [[ -f "$deploy_script" ]]; then
        grep "DEFAULT_REPO=" "$deploy_script" | head -1 | cut -d'"' -f2 | sed 's/.*:-\([^}]*\)}.*/\1/'
    else
        echo "your-org/discovery-service"
    fi
}

check_repository_exists() {
    local repo="$1"
    local auth_header=""

    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth_header="-H Authorization: token $GITHUB_TOKEN"
    fi

    log_info "Checking if repository exists: $repo"

    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" $auth_header "https://api.github.com/repos/$repo")

    case $response_code in
        200)
            log_info "✓ Repository found and accessible"
            return 0
            ;;
        404)
            log_warn "⚠ Repository not found or not accessible"
            log_warn "  This could mean:"
            log_warn "  - Repository doesn't exist"
            log_warn "  - Repository is private and requires GITHUB_TOKEN"
            log_warn "  - Repository name is incorrect"
            return 1
            ;;
        403)
            log_warn "⚠ Access forbidden - you might need a GitHub token"
            return 1
            ;;
        *)
            log_warn "⚠ Unexpected response code: $response_code"
            return 1
            ;;
    esac
}

check_releases() {
    local repo="$1"
    local auth_header=""

    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth_header="-H Authorization: token $GITHUB_TOKEN"
    fi

    log_info "Checking for releases..."

    local releases
    releases=$(curl -s $auth_header "https://api.github.com/repos/$repo/releases" | jq -r '.[].tag_name' 2>/dev/null | head -5)

    if [[ -n "$releases" ]]; then
        log_info "✓ Found releases:"
        echo "$releases" | while read -r release; do
            echo "  - $release"
        done
        return 0
    else
        log_warn "⚠ No releases found"
        log_warn "  You'll need to create a GitHub release with precompiled binaries"
        log_warn "  Expected binary names:"
        log_warn "  - discovery-server-linux-amd64.tar.gz"
        log_warn "  - discovery-client-linux-amd64.tar.gz"
        return 1
    fi
}

update_script_files() {
    local repo="$1"
    local deploy_script="$SCRIPT_DIR/deploy-binary.sh"
    local wrapper_script="$SCRIPT_DIR/deploy.sh"
    local makefile="$PROJECT_DIR/Makefile"

    log_info "Updating script files with repository: $repo"

    # Update deploy-binary.sh
    if [[ -f "$deploy_script" ]]; then
        sed -i.bak "s|DEFAULT_REPO=.*|DEFAULT_REPO=\"\${DISCOVERY_REPO:-$repo}\"|" "$deploy_script"
        log_debug "Updated $deploy_script"
    fi

    # Update deploy.sh
    if [[ -f "$wrapper_script" ]]; then
        sed -i.bak "s|DEFAULT_REPO=.*|DEFAULT_REPO=\"\${DISCOVERY_REPO:-$repo}\"|" "$wrapper_script"
        log_debug "Updated $wrapper_script"
    fi

    # Update Makefile
    if [[ -f "$makefile" ]]; then
        if grep -q "DEFAULT_REPO ?=" "$makefile"; then
            sed -i.bak "s|DEFAULT_REPO ?=.*|DEFAULT_REPO ?= $repo|" "$makefile"
        else
            echo "DEFAULT_REPO ?= $repo" >> "$makefile"
        fi
        log_debug "Updated $makefile"
    fi

    log_info "✓ Script files updated successfully"
    log_info "  Backup files created with .bak extension"
}

create_env_file() {
    local repo="$1"
    local env_file="$PROJECT_DIR/.env.deployment"

    log_info "Creating environment file: $env_file"

    cat > "$env_file" << EOF
# S01 Service Deployment Configuration
# Source this file before running deployment commands:
#   source .env.deployment && make deploy-production

# GitHub repository for binary downloads
export DISCOVERY_REPO="$repo"

# GitHub token for private repositories (optional)
# export GITHUB_TOKEN="your_github_token_here"

# Deployment options
# export DEPLOY_ARGS="--version v1.0.0 --force"

# Debug output
# export DEBUG=true
EOF

    log_info "✓ Environment file created: $env_file"
    echo
    log_info "To use this configuration:"
    log_info "  source .env.deployment"
    log_info "  make deploy-production"
    echo
}

show_configuration() {
    local current_repo
    current_repo=$(get_current_config)

    echo
    echo "Current Configuration:"
    echo "====================="
    echo "Repository: $current_repo"
    echo

    if [[ -f "$PROJECT_DIR/.env.deployment" ]]; then
        echo "Environment file: $PROJECT_DIR/.env.deployment exists"
    else
        echo "Environment file: Not created"
    fi

    echo
    echo "Script Files:"
    for script in "$SCRIPT_DIR/deploy-binary.sh" "$SCRIPT_DIR/deploy.sh"; do
        if [[ -f "$script" ]]; then
            echo "  ✓ $(basename "$script"): exists"
        else
            echo "  ✗ $(basename "$script"): missing"
        fi
    done

    echo
    echo "GitHub Actions:"
    if [[ -f "$PROJECT_DIR/.github/workflows/release.yml" ]]; then
        echo "  ✓ Release workflow: configured"
    else
        echo "  ⚠ Release workflow: not found"
        echo "    Consider setting up automated releases"
    fi

    echo
}

interactive_configuration() {
    print_header

    local current_repo
    current_repo=$(get_current_config)

    echo "Current repository: $current_repo"
    echo

    # Get repository name
    echo -n "Enter GitHub repository (owner/repo-name) [$current_repo]: "
    read -r repo_input

    if [[ -z "$repo_input" ]]; then
        repo_input="$current_repo"
    fi

    # Validate repository format
    if [[ ! "$repo_input" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
        log_error "Invalid repository format. Expected: owner/repository-name"
        exit 1
    fi

    echo
    log_info "Repository set to: $repo_input"

    # Check if repository exists
    if check_repository_exists "$repo_input"; then
        check_releases "$repo_input"
    fi

    echo
    echo "Configuration method:"
    echo "1. Update script files directly (recommended)"
    echo "2. Create environment file (.env.deployment)"
    echo
    echo -n "Choose method [1]: "
    read -r method

    case "${method:-1}" in
        1)
            update_script_files "$repo_input"
            ;;
        2)
            create_env_file "$repo_input"
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac

    echo
    log_info "Configuration completed successfully!"
    echo
    echo "Next steps:"
    echo "1. Ensure your repository has GitHub releases with precompiled binaries"
    echo "2. Test deployment with: make deploy-status"
    echo "3. Deploy with: sudo make deploy-production"
    echo

    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        echo "💡 Tip: Set GITHUB_TOKEN environment variable for private repositories"
        echo "   export GITHUB_TOKEN=your_token_here"
        echo
    fi
}

reset_configuration() {
    log_info "Resetting to default configuration..."

    local deploy_script="$SCRIPT_DIR/deploy-binary.sh"
    local wrapper_script="$SCRIPT_DIR/deploy.sh"
    local makefile="$PROJECT_DIR/Makefile"
    local env_file="$PROJECT_DIR/.env.deployment"

    # Restore from backups if they exist
    for script in "$deploy_script" "$wrapper_script" "$makefile"; do
        if [[ -f "$script.bak" ]]; then
            mv "$script.bak" "$script"
            log_debug "Restored $script from backup"
        fi
    done

    # Remove environment file
    if [[ -f "$env_file" ]]; then
        rm "$env_file"
        log_debug "Removed $env_file"
    fi

    # Reset to default values
    if [[ -f "$deploy_script" ]]; then
        sed -i 's|DEFAULT_REPO=.*|DEFAULT_REPO="${DISCOVERY_REPO:-your-org/discovery-service}"|' "$deploy_script"
    fi

    if [[ -f "$wrapper_script" ]]; then
        sed -i 's|DEFAULT_REPO=.*|DEFAULT_REPO="${DISCOVERY_REPO:-your-org/discovery-service}"|' "$wrapper_script"
    fi

    log_info "✓ Configuration reset to defaults"
}

create_github_workflow_template() {
    local workflow_file="$PROJECT_DIR/.github/workflows/release.yml"
    local workflow_dir="$(dirname "$workflow_file")"

    if [[ -f "$workflow_file" ]]; then
        log_info "GitHub Actions workflow already exists: $workflow_file"
        return 0
    fi

    log_info "Creating GitHub Actions workflow template..."

    mkdir -p "$workflow_dir"

    # The workflow file is already created in the project, so just inform the user
    if [[ ! -f "$workflow_file" ]]; then
        log_warn "GitHub Actions workflow template not found"
        log_info "Consider creating .github/workflows/release.yml for automated releases"
    else
        log_info "✓ GitHub Actions workflow exists: $workflow_file"
    fi
}

# Parse command line arguments
INTERACTIVE=true
REPO=""
CHECK_ONLY=false
RESET=false
ENV_FILE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --repo)
            REPO="$2"
            INTERACTIVE=false
            shift 2
            ;;
        --check)
            CHECK_ONLY=true
            INTERACTIVE=false
            shift
            ;;
        --reset)
            RESET=true
            INTERACTIVE=false
            shift
            ;;
        --env-file)
            ENV_FILE=true
            shift
            ;;
        --interactive)
            INTERACTIVE=true
            shift
            ;;
        --help|-h)
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

# Main execution
main() {
    if [[ "$CHECK_ONLY" == true ]]; then
        show_configuration
        exit 0
    fi

    if [[ "$RESET" == true ]]; then
        reset_configuration
        exit 0
    fi

    if [[ "$INTERACTIVE" == true ]]; then
        interactive_configuration
        exit 0
    fi

    if [[ -n "$REPO" ]]; then
        print_header
        log_info "Configuring repository: $REPO"

        # Validate repository format
        if [[ ! "$REPO" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
            log_error "Invalid repository format. Expected: owner/repository-name"
            exit 1
        fi

        # Check repository
        check_repository_exists "$REPO"

        # Configure
        if [[ "$ENV_FILE" == true ]]; then
            create_env_file "$REPO"
        else
            update_script_files "$REPO"
        fi

        # Create workflow if needed
        create_github_workflow_template

        log_info "✓ Configuration completed for repository: $REPO"
        exit 0
    fi

    # Default to interactive mode
    interactive_configuration
}

# Run main function
main "$@"
