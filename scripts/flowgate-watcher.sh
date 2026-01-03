#!/usr/bin/env bash
#
# flowgate-watcher.sh
# Watches GitHub issues with flowgate labels and dispatches to flowgate CLI
#
# Runs via cron every minute, queries for issues with flowgate* labels,
# determines mode from label, calls flowgate, and removes the label.
#

set -euo pipefail

# Configuration
LOCK_FILE="/var/run/flowgate-watcher.lock"
LOG_FILE="${FLOWGATE_LOG_FILE:-/var/log/flowgate-watcher.log}"
GITHUB_REPO="${GITHUB_REPO:?GITHUB_REPO is required}"
DEFAULT_MODE="${FLOWGATE_MODE:-swarm}"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
}

log_warn() {
    log "WARN" "$@"
}

log_error() {
    log "ERROR" "$@"
}

# Cleanup function
cleanup() {
    rm -f "$LOCK_FILE"
    log_info "Watcher stopped, lock released"
}

# Check if another instance is running
acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local pid
        pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            log_warn "Another instance is running (PID: $pid), exiting"
            exit 0
        else
            log_warn "Stale lock file found, removing"
            rm -f "$LOCK_FILE"
        fi
    fi

    echo $$ > "$LOCK_FILE"
    trap cleanup EXIT
    log_info "Lock acquired (PID: $$)"
}

# Determine mode from label name
get_mode_from_label() {
    local label="$1"

    case "$label" in
        "flowgate:swarm")
            echo "swarm"
            ;;
        "flowgate:hive")
            echo "hive-mind"
            ;;
        "flowgate")
            echo "$DEFAULT_MODE"
            ;;
        *)
            # Unknown flowgate label, use default
            log_warn "Unknown flowgate label: $label, using default mode: $DEFAULT_MODE"
            echo "$DEFAULT_MODE"
            ;;
    esac
}

# Process a single issue
process_issue() {
    local issue_number="$1"
    local label="$2"
    local mode

    mode=$(get_mode_from_label "$label")

    log_info "Processing issue #$issue_number with label '$label' in mode '$mode'"

    # Call flowgate CLI
    if flowgate -m "$mode" "$issue_number"; then
        log_info "Successfully queued issue #$issue_number"

        # Remove the label after successful processing
        if gh issue edit "$issue_number" --repo "$GITHUB_REPO" --remove-label "$label"; then
            log_info "Removed label '$label' from issue #$issue_number"
        else
            log_error "Failed to remove label '$label' from issue #$issue_number"
        fi
    else
        log_error "Failed to process issue #$issue_number"
        return 1
    fi
}

# Query GitHub for issues with flowgate labels
fetch_flowgate_issues() {
    # Query issues with any flowgate* label
    # We use multiple label queries since gh doesn't support wildcards
    local issues_json

    # Get all issues with flowgate-related labels
    issues_json=$(gh issue list \
        --repo "$GITHUB_REPO" \
        --label "flowgate" \
        --label "flowgate:swarm" \
        --label "flowgate:hive" \
        --json number,labels \
        --limit 100 2>/dev/null || echo "[]")

    # If the above doesn't work (labels are OR'd), try individual queries
    if [ "$issues_json" = "[]" ] || [ -z "$issues_json" ]; then
        local flowgate_issues swarm_issues hive_issues

        flowgate_issues=$(gh issue list --repo "$GITHUB_REPO" --label "flowgate" --json number,labels --limit 100 2>/dev/null || echo "[]")
        swarm_issues=$(gh issue list --repo "$GITHUB_REPO" --label "flowgate:swarm" --json number,labels --limit 100 2>/dev/null || echo "[]")
        hive_issues=$(gh issue list --repo "$GITHUB_REPO" --label "flowgate:hive" --json number,labels --limit 100 2>/dev/null || echo "[]")

        # Merge and deduplicate
        issues_json=$(echo "$flowgate_issues $swarm_issues $hive_issues" | jq -s 'add | unique_by(.number)')
    fi

    echo "$issues_json"
}

# Main execution
main() {
    log_info "=== flowgate-watcher started ==="

    # Acquire lock to prevent concurrent runs
    acquire_lock

    # Verify dependencies
    if ! command -v gh &>/dev/null; then
        log_error "gh CLI not found"
        exit 1
    fi

    if ! command -v jq &>/dev/null; then
        log_error "jq not found"
        exit 1
    fi

    if ! command -v flowgate &>/dev/null; then
        log_error "flowgate CLI not found"
        exit 1
    fi

    # Fetch issues with flowgate labels
    log_info "Fetching issues from $GITHUB_REPO with flowgate labels..."
    local issues_json
    issues_json=$(fetch_flowgate_issues)

    # Count issues
    local issue_count
    issue_count=$(echo "$issues_json" | jq 'length')

    if [ "$issue_count" -eq 0 ]; then
        log_info "No issues with flowgate labels found"
        exit 0
    fi

    log_info "Found $issue_count issue(s) to process"

    # Process each issue
    echo "$issues_json" | jq -c '.[]' | while read -r issue; do
        local issue_number
        issue_number=$(echo "$issue" | jq -r '.number')

        # Get flowgate labels for this issue
        local labels
        labels=$(echo "$issue" | jq -r '.labels[].name' | grep -E '^flowgate(:|$)' || true)

        if [ -z "$labels" ]; then
            log_warn "Issue #$issue_number has no flowgate labels, skipping"
            continue
        fi

        # Process with the first matching flowgate label
        # Priority: flowgate:swarm > flowgate:hive > flowgate
        local selected_label
        if echo "$labels" | grep -q "^flowgate:swarm$"; then
            selected_label="flowgate:swarm"
        elif echo "$labels" | grep -q "^flowgate:hive$"; then
            selected_label="flowgate:hive"
        else
            selected_label="flowgate"
        fi

        process_issue "$issue_number" "$selected_label" || true
    done

    log_info "=== flowgate-watcher completed ==="
}

# Run main
main "$@"
