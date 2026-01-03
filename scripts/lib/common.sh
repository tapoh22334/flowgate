#!/usr/bin/env bash
# flowgate common utilities
# Sourced by all flowgate scripts

# Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export NC='\033[0m' # No Color

# Paths
export FLOWGATE_HOME="${FLOWGATE_HOME:-$HOME/.flowgate}"
export FLOWGATE_CONFIG="$FLOWGATE_HOME/config.toml"
export FLOWGATE_REPOS_META="$FLOWGATE_HOME/repos.meta"
export FLOWGATE_REPOS_DIR="$FLOWGATE_HOME/repos"
export FLOWGATE_LOGS_DIR="$FLOWGATE_HOME/logs"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $*"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*" >&2
}

log_step() {
    echo -e "${CYAN}→${NC} $*"
}

# File logging (append to log file)
log_to_file() {
    local logfile="$1"
    shift
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $*" >> "$logfile"
}

# Check if command exists
require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Required command not found: $cmd"
        return 1
    fi
}

# Check all required commands
require_all_cmds() {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        return 1
    fi
}

# Ensure directory exists
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
    fi
}

# Ensure flowgate home directory structure
ensure_flowgate_dirs() {
    ensure_dir "$FLOWGATE_HOME"
    ensure_dir "$FLOWGATE_REPOS_DIR"
    ensure_dir "$FLOWGATE_LOGS_DIR"
    ensure_dir "$FLOWGATE_LOGS_DIR/tasks"
}

# Parse owner/repo format
parse_repo() {
    local repo="$1"
    if [[ ! "$repo" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$ ]]; then
        log_error "Invalid repository format: $repo (expected: owner/repo)"
        return 1
    fi
    echo "$repo"
}

# Get repo directory path
get_repo_dir() {
    local repo="$1"
    echo "$FLOWGATE_REPOS_DIR/$repo"
}

# Get task log file path
get_task_log() {
    local repo="$1"
    local issue="$2"
    local safe_name
    safe_name=$(echo "$repo" | tr '/' '-')
    echo "$FLOWGATE_LOGS_DIR/tasks/${safe_name}-${issue}.log"
}

# Check if repo is in watch list
is_repo_watched() {
    local repo="$1"
    if [[ -f "$FLOWGATE_REPOS_META" ]]; then
        grep -qxF "$repo" "$FLOWGATE_REPOS_META"
    else
        return 1
    fi
}

# Add repo to watch list
add_repo_to_watch() {
    local repo="$1"
    if ! is_repo_watched "$repo"; then
        echo "$repo" >> "$FLOWGATE_REPOS_META"
    fi
}

# Remove repo from watch list
remove_repo_from_watch() {
    local repo="$1"
    if [[ -f "$FLOWGATE_REPOS_META" ]]; then
        local tmp
        tmp=$(mktemp)
        grep -vxF "$repo" "$FLOWGATE_REPOS_META" > "$tmp" || true
        mv "$tmp" "$FLOWGATE_REPOS_META"
    fi
}

# List watched repos
list_watched_repos() {
    if [[ -f "$FLOWGATE_REPOS_META" ]]; then
        cat "$FLOWGATE_REPOS_META"
    fi
}

# Cleanup old logs (older than retention days)
cleanup_old_logs() {
    local retention_days="${1:-30}"
    if [[ -d "$FLOWGATE_LOGS_DIR/tasks" ]]; then
        find "$FLOWGATE_LOGS_DIR/tasks" -name "*.log" -mtime +"$retention_days" -delete 2>/dev/null || true
    fi
}

# Parse mode from label
parse_mode_from_label() {
    local label="$1"
    case "$label" in
        "flowgate:swarm") echo "swarm" ;;
        "flowgate:hive")  echo "hive" ;;
        "flowgate")       echo "default" ;;
        *)                echo "default" ;;
    esac
}

# Get effective mode (use default from config if mode is "default")
get_effective_mode() {
    local mode="$1"
    if [[ "$mode" == "default" ]]; then
        # Source config and get default mode
        if [[ -f "$FLOWGATE_CONFIG" ]]; then
            local default_mode
            default_mode=$(grep -E "^mode\s*=" "$FLOWGATE_CONFIG" | sed 's/.*=\s*"\?\([^"]*\)"\?.*/\1/' | tr -d '[:space:]')
            echo "${default_mode:-swarm}"
        else
            echo "swarm"
        fi
    else
        echo "$mode"
    fi
}

# Print a horizontal line
print_line() {
    local char="${1:--}"
    local width="${2:-60}"
    printf '%*s\n' "$width" '' | tr ' ' "$char"
}

# Print header
print_header() {
    local title="$1"
    echo ""
    print_line "="
    echo -e "${CYAN}$title${NC}"
    print_line "="
    echo ""
}

# Confirm action (returns 0 for yes, 1 for no)
confirm() {
    local prompt="${1:-Are you sure?}"
    local default="${2:-n}"

    local yn_prompt
    if [[ "$default" == "y" ]]; then
        yn_prompt="[Y/n]"
    else
        yn_prompt="[y/N]"
    fi

    read -r -p "$prompt $yn_prompt " response
    response=${response:-$default}

    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# Version info
flowgate_version() {
    echo "flowgate v0.1.0"
}
