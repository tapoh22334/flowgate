#!/usr/bin/env bash
#
# flowgate - Bridge GitHub Issues to claude-flow task execution
#
# Usage:
#   flowgate <issue-number>           Run with default mode
#   flowgate -m <mode> <issue-number> Run with specified mode (swarm/hive)
#   flowgate status                   Show pueue status
#

set -euo pipefail

# ==============================================================================
# Constants
# ==============================================================================
readonly REPO_DIR="/repos/repo"
readonly WORKTREES_DIR="${REPO_DIR}/.worktrees"

# ==============================================================================
# Colors
# ==============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# ==============================================================================
# Logging functions
# ==============================================================================
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# ==============================================================================
# Usage
# ==============================================================================
usage() {
    cat <<EOF
Usage: flowgate [OPTIONS] <issue-number>
       flowgate status

Bridge GitHub Issues to claude-flow task execution.

Arguments:
  issue-number    GitHub issue number to process
  status          Show pueue queue status

Options:
  -m, --mode MODE  Execution mode: swarm or hive (default: \$FLOWGATE_MODE or swarm)
  -h, --help       Show this help message

Environment:
  GITHUB_REPO      Target repository (e.g., owner/repo) [required]
  FLOWGATE_MODE    Default execution mode (swarm/hive) [default: swarm]

Examples:
  flowgate 123              Process issue #123 with default mode
  flowgate -m hive 123      Process issue #123 with hive-mind mode
  flowgate status           Show current queue status
EOF
}

# ==============================================================================
# Validation
# ==============================================================================
validate_environment() {
    if [[ -z "${GITHUB_REPO:-}" ]]; then
        log_error "GITHUB_REPO environment variable is not set"
        exit 1
    fi

    if ! command -v gh &>/dev/null; then
        log_error "gh CLI is not installed"
        exit 1
    fi

    if ! command -v pueue &>/dev/null; then
        log_error "pueue is not installed"
        exit 1
    fi

    if ! command -v claude-flow &>/dev/null; then
        log_error "claude-flow is not installed"
        exit 1
    fi

    if [[ ! -d "${REPO_DIR}" ]]; then
        log_error "Repository directory not found: ${REPO_DIR}"
        exit 1
    fi
}

validate_mode() {
    local mode="$1"
    if [[ "${mode}" != "swarm" && "${mode}" != "hive" ]]; then
        log_error "Invalid mode: ${mode}. Must be 'swarm' or 'hive'"
        exit 1
    fi
}

validate_issue_number() {
    local issue="$1"
    if ! [[ "${issue}" =~ ^[0-9]+$ ]]; then
        log_error "Invalid issue number: ${issue}"
        exit 1
    fi
}

# ==============================================================================
# Commands
# ==============================================================================
cmd_status() {
    log_info "Fetching pueue status..."
    pueue status
}

cmd_process_issue() {
    local mode="$1"
    local issue_number="$2"

    log_info "Processing issue #${issue_number} with mode: ${mode}"

    # Fetch issue data
    log_info "Fetching issue from ${GITHUB_REPO}..."
    local issue_data
    issue_data=$(gh issue view "${issue_number}" --repo "${GITHUB_REPO}" --json body,title 2>&1) || {
        log_error "Failed to fetch issue #${issue_number}: ${issue_data}"
        exit 1
    }

    local title
    local body
    title=$(echo "${issue_data}" | jq -r '.title')
    body=$(echo "${issue_data}" | jq -r '.body')

    if [[ -z "${title}" || "${title}" == "null" ]]; then
        log_error "Issue #${issue_number} not found or has no title"
        exit 1
    fi

    log_success "Fetched issue: ${title}"

    # Create worktree
    local branch_name="issue-${issue_number}"
    local worktree_path="${WORKTREES_DIR}/${branch_name}"

    cd "${REPO_DIR}"

    # Create worktrees directory if not exists
    mkdir -p "${WORKTREES_DIR}"

    # Check if worktree already exists
    if [[ -d "${worktree_path}" ]]; then
        log_warn "Worktree already exists: ${worktree_path}"
        log_info "Removing existing worktree..."
        git worktree remove --force "${worktree_path}" 2>/dev/null || true
        git branch -D "${branch_name}" 2>/dev/null || true
    fi

    log_info "Creating worktree: ${worktree_path}"
    git worktree add -b "${branch_name}" "${worktree_path}" || {
        log_error "Failed to create worktree"
        exit 1
    }
    log_success "Worktree created"

    # Generate task prompt
    local task_prompt
    task_prompt=$(generate_task_prompt "${title}" "${body}" "${issue_number}")

    # Determine claude-flow command based on mode
    local flow_mode
    if [[ "${mode}" == "hive" ]]; then
        flow_mode="hive-mind"
    else
        flow_mode="swarm"
    fi

    # Queue the task with pueue
    local pueue_command="cd '${worktree_path}' && claude-flow ${flow_mode} '${task_prompt}'"

    log_info "Queuing task with pueue..."
    local task_id
    task_id=$(pueue add --print-task-id -- bash -c "${pueue_command}") || {
        log_error "Failed to queue task"
        exit 1
    }

    log_success "Task queued successfully!"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Issue:${NC}     #${issue_number} - ${title}"
    echo -e "${GREEN}Mode:${NC}      ${mode} (${flow_mode})"
    echo -e "${GREEN}Worktree:${NC}  ${worktree_path}"
    echo -e "${GREEN}Task ID:${NC}   ${task_id}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "Use ${YELLOW}flowgate status${NC} to check progress"
}

generate_task_prompt() {
    local title="$1"
    local body="$2"
    local issue_number="$3"

    # Escape single quotes in body for shell safety
    local escaped_body="${body//\'/\'\\\'\'}"
    local escaped_title="${title//\'/\'\\\'\'}"

    cat <<EOF
Implement the following GitHub issue and create a Pull Request.

## Issue #${issue_number}: ${escaped_title}

${escaped_body}

---

## Instructions

1. Implement the changes described in the issue above
2. Make sure to test your implementation
3. Commit your changes with clear, descriptive commit messages
4. Create a Pull Request using the following command:

   gh pr create --title "Fix #${issue_number}: ${escaped_title}" --body "Closes #${issue_number}

## Summary

[Describe what was implemented]

## Changes

[List the main changes]

## Testing

[Describe how it was tested]"

Make sure the PR references the issue number so it will be automatically linked.
EOF
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    # Default mode from environment or fallback to swarm
    local mode="${FLOWGATE_MODE:-swarm}"
    local issue_number=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -m|--mode)
                if [[ -z "${2:-}" ]]; then
                    log_error "Mode requires a value"
                    usage
                    exit 1
                fi
                mode="$2"
                shift 2
                ;;
            status)
                validate_environment
                cmd_status
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                issue_number="$1"
                shift
                ;;
        esac
    done

    # Validate
    if [[ -z "${issue_number}" ]]; then
        log_error "Issue number is required"
        usage
        exit 1
    fi

    validate_environment
    validate_mode "${mode}"
    validate_issue_number "${issue_number}"

    # Process the issue
    cmd_process_issue "${mode}" "${issue_number}"
}

main "$@"
