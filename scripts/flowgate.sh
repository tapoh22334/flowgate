#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# flowgate - Bridge GitHub Issues to claude-flow task execution via pueue
# =============================================================================

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
readonly FLOWGATE_DIR="${HOME}/.flowgate"
readonly REPOS_META="${FLOWGATE_DIR}/repos.meta"
readonly CONFIG_FILE="${FLOWGATE_DIR}/config.toml"
readonly REPOS_DIR="${FLOWGATE_DIR}/repos"
readonly LOGS_DIR="${FLOWGATE_DIR}/logs"
readonly TASKS_LOG_DIR="${LOGS_DIR}/tasks"

readonly VERSION="0.1.0"

# -----------------------------------------------------------------------------
# Colors
# -----------------------------------------------------------------------------
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Utility Functions
# -----------------------------------------------------------------------------
info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

die() {
    error "$@"
    exit 1
}

# -----------------------------------------------------------------------------
# Config Functions
# -----------------------------------------------------------------------------
get_config() {
    local key="$1"
    local default="${2:-}"

    if [[ -f "$CONFIG_FILE" ]]; then
        # Simple TOML parsing for key = "value" or key = value
        local value
        value=$(grep -E "^${key}\s*=" "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/.*=\s*"\?\([^"]*\)"\?.*/\1/' || true)
        if [[ -n "$value" ]]; then
            echo "$value"
            return
        fi
    fi
    echo "$default"
}

get_default_mode() {
    get_config "mode" "swarm"
}

get_pueue_group() {
    get_config "group" "flowgate"
}

# -----------------------------------------------------------------------------
# Initialization
# -----------------------------------------------------------------------------
ensure_dirs() {
    mkdir -p "$FLOWGATE_DIR"
    mkdir -p "$REPOS_DIR"
    mkdir -p "$LOGS_DIR"
    mkdir -p "$TASKS_LOG_DIR"
    touch "$REPOS_META"
}

check_dependencies() {
    local missing=()

    command -v gh >/dev/null 2>&1 || missing+=("gh")
    command -v pueue >/dev/null 2>&1 || missing+=("pueue")
    command -v git >/dev/null 2>&1 || missing+=("git")

    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing dependencies: ${missing[*]}"
    fi
}

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------
show_help() {
    cat << EOF
${BOLD}flowgate${NC} - Bridge GitHub Issues to claude-flow task execution

${BOLD}USAGE:${NC}
    flowgate <owner/repo> [OPTIONS] <issue-number>
    flowgate status
    flowgate repo <subcommand>

${BOLD}COMMANDS:${NC}
    ${CYAN}<owner/repo> <issue-number>${NC}
        Queue an issue for processing

    ${CYAN}status${NC}
        Show pueue queue status

    ${CYAN}repo add <owner/repo>${NC}
        Add repository to watch list and clone it

    ${CYAN}repo remove <owner/repo>${NC}
        Remove repository from watch list

    ${CYAN}repo list${NC}
        List watched repositories

${BOLD}OPTIONS:${NC}
    ${CYAN}-m, --mode <mode>${NC}
        Execution mode: swarm | hive (default: ${YELLOW}$(get_default_mode)${NC})

    ${CYAN}-h, --help${NC}
        Show this help message

    ${CYAN}-v, --version${NC}
        Show version

${BOLD}EXAMPLES:${NC}
    ${GREEN}# Add a repository to watch${NC}
    flowgate repo add owner/my-project

    ${GREEN}# Queue an issue with default mode${NC}
    flowgate owner/my-project 123

    ${GREEN}# Queue an issue with hive-mind mode${NC}
    flowgate owner/my-project -m hive 123

    ${GREEN}# Check queue status${NC}
    flowgate status

${BOLD}CONFIGURATION:${NC}
    Config file: ${YELLOW}~/.flowgate/config.toml${NC}
    Repos file:  ${YELLOW}~/.flowgate/repos.meta${NC}
    Repos dir:   ${YELLOW}~/.flowgate/repos/${NC}

EOF
}

show_version() {
    echo "flowgate version ${VERSION}"
}

# -----------------------------------------------------------------------------
# Repository Management
# -----------------------------------------------------------------------------
repo_add() {
    local repo="$1"

    # Validate repo format
    if [[ ! "$repo" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$ ]]; then
        die "Invalid repository format. Expected: owner/repo"
    fi

    local owner="${repo%/*}"
    local name="${repo#*/}"
    local repo_path="${REPOS_DIR}/${owner}/${name}"

    info "Adding repository: ${CYAN}${repo}${NC}"

    # Check if already exists
    if grep -qxF "$repo" "$REPOS_META" 2>/dev/null; then
        warn "Repository already in watch list"
    else
        echo "$repo" >> "$REPOS_META"
        success "Added to watch list"
    fi

    # Clone if not exists
    if [[ -d "$repo_path/.git" ]]; then
        info "Repository already cloned at ${repo_path}"
    else
        info "Cloning repository..."
        mkdir -p "${REPOS_DIR}/${owner}"
        if gh repo clone "$repo" "$repo_path"; then
            success "Cloned to ${repo_path}"
        else
            die "Failed to clone repository"
        fi
    fi

    echo ""
    success "Ready! Add '${CYAN}flowgate${NC}' label to any issue in ${CYAN}${repo}${NC}."
}

repo_remove() {
    local repo="$1"

    if [[ ! -f "$REPOS_META" ]]; then
        die "No repositories configured"
    fi

    if ! grep -qxF "$repo" "$REPOS_META" 2>/dev/null; then
        die "Repository not in watch list: ${repo}"
    fi

    # Remove from list
    local tmp
    tmp=$(mktemp)
    grep -vxF "$repo" "$REPOS_META" > "$tmp" || true
    mv "$tmp" "$REPOS_META"

    success "Removed ${CYAN}${repo}${NC} from watch list"
    info "Note: Repository files in ${REPOS_DIR} were not deleted"
}

repo_list() {
    if [[ ! -f "$REPOS_META" ]] || [[ ! -s "$REPOS_META" ]]; then
        info "No repositories configured"
        echo ""
        echo "Add a repository with: ${CYAN}flowgate repo add owner/repo${NC}"
        return
    fi

    echo -e "${BOLD}Watched Repositories:${NC}"
    echo ""
    while IFS= read -r repo; do
        [[ -z "$repo" ]] && continue
        local repo_path="${REPOS_DIR}/${repo}"
        if [[ -d "$repo_path/.git" ]]; then
            echo -e "  ${GREEN}*${NC} ${repo} ${CYAN}(cloned)${NC}"
        else
            echo -e "  ${YELLOW}!${NC} ${repo} ${YELLOW}(not cloned)${NC}"
        fi
    done < "$REPOS_META"
    echo ""
}

handle_repo_command() {
    local subcommand="${1:-}"
    shift || true

    case "$subcommand" in
        add)
            [[ -z "${1:-}" ]] && die "Usage: flowgate repo add <owner/repo>"
            repo_add "$1"
            ;;
        remove|rm)
            [[ -z "${1:-}" ]] && die "Usage: flowgate repo remove <owner/repo>"
            repo_remove "$1"
            ;;
        list|ls)
            repo_list
            ;;
        "")
            die "Usage: flowgate repo <add|remove|list>"
            ;;
        *)
            die "Unknown repo subcommand: ${subcommand}"
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Status
# -----------------------------------------------------------------------------
show_status() {
    local group
    group=$(get_pueue_group)

    echo -e "${BOLD}flowgate Queue Status${NC}"
    echo ""

    # Check if pueued is running
    if ! pueue status >/dev/null 2>&1; then
        warn "pueued is not running"
        echo "Start with: ${CYAN}pueued -d${NC}"
        return 1
    fi

    # Check if group exists
    if pueue group | grep -q "^${group}"; then
        pueue status --group "$group"
    else
        info "No '${group}' group found. Tasks may be in default group."
        pueue status
    fi
}

# -----------------------------------------------------------------------------
# Queue Issue
# -----------------------------------------------------------------------------
queue_issue() {
    local repo="$1"
    local issue_number="$2"
    local mode="$3"

    # Validate inputs
    if [[ ! "$repo" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$ ]]; then
        die "Invalid repository format. Expected: owner/repo"
    fi

    if [[ ! "$issue_number" =~ ^[0-9]+$ ]]; then
        die "Invalid issue number: ${issue_number}"
    fi

    if [[ "$mode" != "swarm" && "$mode" != "hive" ]]; then
        die "Invalid mode: ${mode}. Expected: swarm | hive"
    fi

    local owner="${repo%/*}"
    local name="${repo#*/}"
    local repo_path="${REPOS_DIR}/${owner}/${name}"
    local branch="issue-${issue_number}"
    local log_file="${TASKS_LOG_DIR}/${owner}-${name}-${issue_number}.log"
    local group
    group=$(get_pueue_group)

    info "Queueing issue: ${CYAN}${repo}#${issue_number}${NC} (mode: ${YELLOW}${mode}${NC})"

    # Check repo exists
    if [[ ! -d "$repo_path/.git" ]]; then
        die "Repository not cloned. Run: ${CYAN}flowgate repo add ${repo}${NC}"
    fi

    # Fetch issue
    info "Fetching issue..."
    local issue_body
    local issue_title
    if ! issue_body=$(gh issue view "$issue_number" --repo "$repo" --json body -q .body 2>&1); then
        die "Failed to fetch issue: ${issue_body}"
    fi
    if ! issue_title=$(gh issue view "$issue_number" --repo "$repo" --json title -q .title 2>&1); then
        die "Failed to fetch issue title: ${issue_title}"
    fi

    success "Fetched issue: ${issue_title}"

    # Build task content and write to file (safer than command line embedding)
    local task_file="${TASKS_LOG_DIR}/${owner}-${name}-${issue_number}.task"
    cat > "$task_file" << TASK_EOF
# ${issue_title}

${issue_body}

---
完了後、gh CLIを使ってPRを作成してください。
- ブランチ: ${branch}
- Issue: #${issue_number}
TASK_EOF

    # Build claude-flow command
    local claude_cmd
    if [[ "$mode" == "hive" ]]; then
        claude_cmd="npx claude-flow@alpha hive-mind"
    else
        claude_cmd="npx claude-flow@alpha swarm"
    fi

    # Build pueue command (task content read from file to prevent injection)
    local pueue_cmd
    pueue_cmd=$(cat << CMD_EOF
cd "${repo_path}" && \\
git fetch origin && \\
git checkout main && \\
git pull origin main && \\
git worktree add -b "${branch}" ".worktrees/${branch}" && \\
cd ".worktrees/${branch}" && \\
${claude_cmd} "\$(cat '${task_file}')" --claude 2>&1 | tee "${log_file}"
CMD_EOF
)

    # Ensure pueue group exists
    if ! pueue group 2>/dev/null | grep -q "^${group}"; then
        info "Creating pueue group: ${group}"
        pueue group add "$group" 2>/dev/null || true
    fi

    # Add to pueue
    info "Adding to pueue queue..."
    local task_id
    if task_id=$(pueue add --group "$group" --print-task-id -- bash -c "$pueue_cmd" 2>&1); then
        success "Queued as task ${CYAN}#${task_id}${NC}"
        echo ""
        echo "Monitor with:"
        echo "  ${CYAN}pueue status --group ${group}${NC}"
        echo "  ${CYAN}pueue log ${task_id}${NC}"
        echo ""
        echo "Log file: ${YELLOW}${log_file}${NC}"
    else
        die "Failed to queue task: ${task_id}"
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    ensure_dirs

    # No arguments
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    # Parse first argument
    local cmd="$1"
    shift

    case "$cmd" in
        -h|--help|help)
            show_help
            exit 0
            ;;
        -v|--version|version)
            show_version
            exit 0
            ;;
        status)
            check_dependencies
            show_status
            exit 0
            ;;
        repo)
            check_dependencies
            handle_repo_command "$@"
            exit 0
            ;;
        *)
            # Assume it's owner/repo
            check_dependencies

            local repo="$cmd"
            local mode
            mode=$(get_default_mode)
            local issue_number=""

            # Parse remaining arguments
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    -m|--mode)
                        [[ -z "${2:-}" ]] && die "Mode requires an argument"
                        mode="$2"
                        shift 2
                        ;;
                    -h|--help)
                        show_help
                        exit 0
                        ;;
                    *)
                        if [[ -z "$issue_number" ]]; then
                            issue_number="$1"
                        else
                            die "Unexpected argument: $1"
                        fi
                        shift
                        ;;
                esac
            done

            if [[ -z "$issue_number" ]]; then
                die "Issue number required. Usage: flowgate <owner/repo> <issue-number>"
            fi

            queue_issue "$repo" "$issue_number" "$mode"
            ;;
    esac
}

main "$@"
