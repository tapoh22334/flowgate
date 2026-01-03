#!/bin/bash
#
# flowgate init.sh - Setup wizard for flowgate
#
# Usage:
#   ./init.sh owner/repo      - Full setup
#   ./init.sh --reauth        - Re-authenticate only
#   ./init.sh --reset owner/repo - Full reset and setup
#

set -e

# ============================================================================
# Colors and Formatting
# ============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m' # No Color

# Status indicators
readonly CHECK="${GREEN}[✓]${NC}"
readonly PENDING="${DIM}[ ]${NC}"
readonly ARROW="${CYAN}→${NC}"
readonly CROSS="${RED}[✗]${NC}"

# ============================================================================
# Helper Functions
# ============================================================================
print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}flowgate setup${NC}"
    echo -e "${DIM}==============${NC}"
}

print_status() {
    local status="$1"
    local message="$2"
    echo -e "${status} ${message}"
}

print_step() {
    local message="$1"
    echo ""
    echo -e "${ARROW} ${BOLD}${message}${NC}"
}

print_error() {
    local message="$1"
    echo -e "${RED}Error: ${message}${NC}" >&2
}

print_warning() {
    local message="$1"
    echo -e "${YELLOW}Warning: ${message}${NC}"
}

print_info() {
    local message="$1"
    echo -e "  ${DIM}${message}${NC}"
}

# ============================================================================
# Validation Functions
# ============================================================================
validate_repo_format() {
    local repo="$1"
    if [[ ! "$repo" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
        print_error "Invalid repository format. Expected: owner/repo"
        exit 1
    fi
}

# ============================================================================
# Pre-check Functions
# ============================================================================
check_docker() {
    if command -v docker &> /dev/null && docker --version &> /dev/null; then
        return 0
    else
        return 1
    fi
}

check_docker_compose() {
    if docker compose version &> /dev/null; then
        return 0
    else
        return 1
    fi
}

check_docker_running() {
    if docker info &> /dev/null; then
        return 0
    else
        return 1
    fi
}

check_container_running() {
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^flowgate$'; then
        return 0
    else
        return 1
    fi
}

run_prechecks() {
    local all_ok=true

    echo ""
    if check_docker; then
        print_status "$CHECK" "Docker installed"
    else
        print_status "$CROSS" "Docker not found"
        print_info "Please install Docker: https://docs.docker.com/get-docker/"
        all_ok=false
    fi

    if check_docker_compose; then
        print_status "$CHECK" "Docker Compose available"
    else
        print_status "$CROSS" "Docker Compose not found"
        print_info "Please install Docker Compose: https://docs.docker.com/compose/install/"
        all_ok=false
    fi

    if check_docker_running; then
        print_status "$CHECK" "Docker daemon running"
    else
        print_status "$CROSS" "Docker daemon not running"
        print_info "Please start Docker Desktop or the Docker daemon"
        all_ok=false
    fi

    if [ "$all_ok" = false ]; then
        echo ""
        print_error "Pre-checks failed. Please fix the above issues and try again."
        exit 1
    fi
}

# ============================================================================
# Setup Functions
# ============================================================================
generate_env() {
    local repo="$1"

    print_step "Generating .env file..."

    # Create .env from template or generate new
    cat > .env << EOF
# flowgate configuration
GITHUB_REPO=${repo}
FLOWGATE_MODE=swarm
POLL_INTERVAL=60
PUEUE_PARALLEL=2
EOF

    print_status "$CHECK" ".env generated (GITHUB_REPO=${repo})"
}

build_container() {
    print_step "Building container..."

    if docker compose build --quiet; then
        print_status "$CHECK" "Container built"
    else
        print_status "$CROSS" "Container build failed"
        print_info "Hint: Check Dockerfile and docker-compose.yml for errors"
        exit 1
    fi
}

start_container() {
    print_step "Starting container..."

    if docker compose up -d; then
        # Wait for container to be ready
        sleep 2
        if check_container_running; then
            print_status "$CHECK" "Container started"
        else
            print_status "$CROSS" "Container failed to start"
            print_info "Hint: Check logs with 'docker compose logs'"
            exit 1
        fi
    else
        print_status "$CROSS" "Failed to start container"
        exit 1
    fi
}

stop_container() {
    print_step "Stopping container..."

    if docker compose down 2>/dev/null; then
        print_status "$CHECK" "Container stopped"
    else
        print_info "No container to stop"
    fi
}

# ============================================================================
# Authentication Functions
# ============================================================================
auth_github() {
    print_step "Starting GitHub authentication..."

    # Check if already authenticated
    if docker exec flowgate gh auth status &>/dev/null; then
        print_status "$CHECK" "GitHub already authenticated"
        return 0
    fi

    echo ""
    print_info "GitHub uses device code authentication."
    print_info "A code will be shown below. Open the URL and enter the code."
    echo ""

    # Run gh auth login with web flow
    # The --web flag triggers device code flow
    if docker exec -it flowgate gh auth login --hostname github.com --git-protocol https --web; then
        echo ""
        print_status "$CHECK" "GitHub authenticated"
    else
        echo ""
        print_status "$CROSS" "GitHub authentication failed"
        print_info "Hint: Run './init.sh --reauth' to try again"
        return 1
    fi
}

auth_claude() {
    print_step "Starting Claude authentication..."

    # Check if already authenticated
    if docker exec flowgate claude --version &>/dev/null; then
        # Try a simple command to check auth status
        if docker exec flowgate sh -c 'test -f ~/.claude/.credentials.json' 2>/dev/null; then
            print_status "$CHECK" "Claude already authenticated"
            return 0
        fi
    fi

    echo ""
    print_info "Claude uses OAuth authentication."
    print_info "A URL will be displayed. Open it in your browser to authenticate."
    echo ""

    # Run claude login
    if docker exec -it flowgate claude login; then
        echo ""
        print_status "$CHECK" "Claude authenticated"
    else
        echo ""
        print_status "$CROSS" "Claude authentication failed"
        print_info "Hint: Run './init.sh --reauth' to try again"
        return 1
    fi
}

# ============================================================================
# Repository Functions
# ============================================================================
clone_repository() {
    local repo="$1"

    print_step "Cloning repository..."

    # Check if already cloned
    if docker exec flowgate test -d /repos/repo/.git 2>/dev/null; then
        print_status "$CHECK" "Repository already cloned"

        # Update the remote URL in case repo changed
        docker exec flowgate git -C /repos/repo remote set-url origin "https://github.com/${repo}.git" 2>/dev/null || true

        print_info "Updating remote to https://github.com/${repo}.git"
        return 0
    fi

    # Create repos directory if needed
    docker exec flowgate mkdir -p /repos

    # Clone the repository
    if docker exec flowgate git clone "https://github.com/${repo}.git" /repos/repo; then
        print_status "$CHECK" "${repo} cloned"
    else
        print_status "$CROSS" "Failed to clone repository"
        print_info "Hint: Make sure the repository exists and you have access"
        return 1
    fi
}

# ============================================================================
# Reset Function
# ============================================================================
do_reset() {
    print_step "Resetting flowgate..."

    # Stop and remove containers
    docker compose down -v 2>/dev/null || true

    # Remove .env
    rm -f .env

    # Remove repos directory
    rm -rf ./repos

    print_status "$CHECK" "Reset complete"
}

# ============================================================================
# Status Display
# ============================================================================
show_status() {
    local repo="${1:-}"

    echo ""

    # Docker status
    if check_docker_running; then
        print_status "$CHECK" "Docker running"
    else
        print_status "$PENDING" "Docker running"
    fi

    # Container status
    if check_container_running; then
        print_status "$CHECK" "Container running"
    else
        print_status "$PENDING" "Container running"
    fi

    # GitHub auth status
    if check_container_running && docker exec flowgate gh auth status &>/dev/null; then
        print_status "$CHECK" "GitHub authenticated"
    else
        print_status "$PENDING" "GitHub authenticated"
    fi

    # Claude auth status
    if check_container_running && docker exec flowgate sh -c 'test -f ~/.claude/.credentials.json' 2>/dev/null; then
        print_status "$CHECK" "Claude authenticated"
    else
        print_status "$PENDING" "Claude authenticated"
    fi

    # Repository status
    if check_container_running && docker exec flowgate test -d /repos/repo/.git 2>/dev/null; then
        print_status "$CHECK" "Repository cloned"
    else
        print_status "$PENDING" "Repository cloned"
    fi
}

# ============================================================================
# Completion Message
# ============================================================================
show_completion() {
    local repo="$1"

    echo ""
    echo -e "${GREEN}${BOLD}Setup complete!${NC}"
    echo ""
    echo -e "Add '${CYAN}flowgate${NC}' label to any issue in ${BOLD}${repo}${NC} to start."
    echo ""
    echo -e "${DIM}Useful commands:${NC}"
    echo -e "  ${CYAN}docker exec flowgate flowgate status${NC}  - Check queue status"
    echo -e "  ${CYAN}docker exec flowgate flowgate 123${NC}     - Manually trigger issue #123"
    echo -e "  ${CYAN}docker compose logs -f${NC}                - View logs"
    echo ""
}

# ============================================================================
# Usage
# ============================================================================
show_usage() {
    echo "Usage: $0 [OPTIONS] [owner/repo]"
    echo ""
    echo "Options:"
    echo "  --reauth              Re-authenticate GitHub and Claude only"
    echo "  --reset owner/repo    Full reset and setup"
    echo "  --help, -h            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 takoh/myrepo       Full setup for takoh/myrepo"
    echo "  $0 --reauth           Re-authenticate without rebuilding"
    echo "  $0 --reset takoh/myrepo  Reset everything and setup fresh"
    echo ""
}

# ============================================================================
# Main Flow
# ============================================================================
main() {
    local mode="full"
    local repo=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reauth)
                mode="reauth"
                shift
                ;;
            --reset)
                mode="reset"
                shift
                if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
                    repo="$1"
                    shift
                fi
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [ -z "$repo" ]; then
                    repo="$1"
                else
                    print_error "Unexpected argument: $1"
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Validate arguments
    case "$mode" in
        full)
            if [ -z "$repo" ]; then
                print_error "Repository is required for full setup"
                show_usage
                exit 1
            fi
            validate_repo_format "$repo"
            ;;
        reset)
            if [ -z "$repo" ]; then
                print_error "Repository is required for reset"
                show_usage
                exit 1
            fi
            validate_repo_format "$repo"
            ;;
        reauth)
            # repo is optional for reauth
            if [ -n "$repo" ]; then
                validate_repo_format "$repo"
            fi
            ;;
    esac

    # Show header
    print_header

    # Run pre-checks
    run_prechecks

    # Execute based on mode
    case "$mode" in
        full)
            show_status "$repo"
            echo ""

            generate_env "$repo"
            build_container
            start_container
            auth_github
            auth_claude
            clone_repository "$repo"

            show_completion "$repo"
            ;;

        reauth)
            # Ensure container is running
            if ! check_container_running; then
                print_error "Container is not running. Run full setup first: ./init.sh owner/repo"
                exit 1
            fi

            show_status
            echo ""

            auth_github
            auth_claude

            # Optionally clone if repo provided
            if [ -n "$repo" ]; then
                clone_repository "$repo"
            fi

            echo ""
            echo -e "${GREEN}${BOLD}Re-authentication complete!${NC}"
            echo ""
            ;;

        reset)
            echo ""
            echo -e "${YELLOW}${BOLD}Warning:${NC} This will remove all data and start fresh."
            echo -n "Continue? [y/N] "
            read -r confirm

            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo "Aborted."
                exit 0
            fi

            do_reset

            # Run full setup
            generate_env "$repo"
            build_container
            start_container
            auth_github
            auth_claude
            clone_repository "$repo"

            show_completion "$repo"
            ;;
    esac
}

# Run main
main "$@"
