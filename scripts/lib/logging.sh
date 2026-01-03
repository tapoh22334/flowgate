#!/usr/bin/env bash
# flowgate logging utilities
# Advanced logging with task tracking and Issue comments

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Log levels
declare -A LOG_LEVELS=(
    [DEBUG]=0
    [INFO]=1
    [WARN]=2
    [ERROR]=3
)

# Current log level (default: INFO)
FLOWGATE_LOG_LEVEL="${FLOWGATE_LOG_LEVEL:-INFO}"

# Get numeric log level
get_log_level() {
    local level="${1:-INFO}"
    echo "${LOG_LEVELS[$level]:-1}"
}

# Check if should log at this level
should_log() {
    local msg_level="$1"
    local current_level
    current_level=$(get_log_level "$FLOWGATE_LOG_LEVEL")
    local check_level
    check_level=$(get_log_level "$msg_level")
    [[ $check_level -ge $current_level ]]
}

# Log message with level and optional file
log_msg() {
    local level="$1"
    local message="$2"
    local logfile="${3:-}"

    if ! should_log "$level"; then
        return 0
    fi

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local formatted="[$timestamp] [$level] $message"

    # Console output with colors
    case "$level" in
        DEBUG) echo -e "${CYAN}$formatted${NC}" ;;
        INFO)  echo -e "${BLUE}$formatted${NC}" ;;
        WARN)  echo -e "${YELLOW}$formatted${NC}" ;;
        ERROR) echo -e "${RED}$formatted${NC}" >&2 ;;
    esac

    # File output (no colors)
    if [[ -n "$logfile" ]]; then
        echo "$formatted" >> "$logfile"
    fi
}

# Task-specific logging
log_task() {
    local repo="$1"
    local issue="$2"
    local level="$3"
    local message="$4"

    local logfile
    logfile=$(get_task_log "$repo" "$issue")
    ensure_dir "$(dirname "$logfile")"

    log_msg "$level" "[$repo#$issue] $message" "$logfile"
}

# Watcher logging
log_watcher() {
    local level="$1"
    local message="$2"

    local logfile="$FLOWGATE_LOGS_DIR/watcher.log"
    ensure_dir "$FLOWGATE_LOGS_DIR"

    log_msg "$level" "[watcher] $message" "$logfile"
}

# Post comment to GitHub Issue
gh_comment() {
    local repo="$1"
    local issue="$2"
    local body="$3"

    if command -v gh &> /dev/null; then
        gh issue comment "$issue" --repo "$repo" --body "$body" 2>/dev/null || true
    fi
}

# Post task start comment
post_task_start() {
    local repo="$1"
    local issue="$2"
    local mode="$3"

    local logfile
    logfile=$(get_task_log "$repo" "$issue")

    local body
    body=$(cat <<EOF
:rocket: **flowgate: タスク開始** ($mode)

ログ: \`$logfile\`
EOF
)
    gh_comment "$repo" "$issue" "$body"
    log_task "$repo" "$issue" "INFO" "Task started (mode: $mode)"
}

# Post task success comment
post_task_success() {
    local repo="$1"
    local issue="$2"
    local pr_number="${3:-}"

    local body
    if [[ -n "$pr_number" ]]; then
        body=":white_check_mark: **flowgate: 完了**

PR: #$pr_number"
    else
        body=":white_check_mark: **flowgate: 完了**"
    fi

    gh_comment "$repo" "$issue" "$body"
    log_task "$repo" "$issue" "INFO" "Task completed successfully (PR: ${pr_number:-N/A})"
}

# Post task failure comment
post_task_failure() {
    local repo="$1"
    local issue="$2"
    local error_msg="${3:-Unknown error}"

    local logfile
    logfile=$(get_task_log "$repo" "$issue")

    # Get last 100 lines of log
    local log_tail=""
    if [[ -f "$logfile" ]]; then
        log_tail=$(tail -100 "$logfile" 2>/dev/null || echo "ログを取得できませんでした")
    fi

    local body
    body=$(cat <<EOF
:x: **flowgate: 失敗**

\`\`\`
$error_msg
\`\`\`

<details>
<summary>エラーログ（末尾100行）</summary>

\`\`\`
$log_tail
\`\`\`

</details>

フルログ: \`$logfile\`
EOF
)
    gh_comment "$repo" "$issue" "$body"
    log_task "$repo" "$issue" "ERROR" "Task failed: $error_msg"
}

# Post task timeout comment
post_task_timeout() {
    local repo="$1"
    local issue="$2"
    local timeout_hours="${3:-6}"

    local logfile
    logfile=$(get_task_log "$repo" "$issue")

    local body
    body=$(cat <<EOF
:stopwatch: **flowgate: タイムアウト** (${timeout_hours}時間超過)

フルログ: \`$logfile\`
EOF
)
    gh_comment "$repo" "$issue" "$body"
    log_task "$repo" "$issue" "WARN" "Task timed out after ${timeout_hours} hours"
}

# Update Issue labels
update_issue_label() {
    local repo="$1"
    local issue="$2"
    local remove_label="$3"
    local add_label="${4:-}"

    if command -v gh &> /dev/null; then
        # Remove old label
        if [[ -n "$remove_label" ]]; then
            gh issue edit "$issue" --repo "$repo" --remove-label "$remove_label" 2>/dev/null || true
        fi

        # Add new label
        if [[ -n "$add_label" ]]; then
            gh issue edit "$issue" --repo "$repo" --add-label "$add_label" 2>/dev/null || true
        fi
    fi
}

# Set processing label
set_processing_label() {
    local repo="$1"
    local issue="$2"
    local original_label="$3"

    update_issue_label "$repo" "$issue" "$original_label" "flowgate:processing"
    log_task "$repo" "$issue" "INFO" "Label changed: $original_label -> flowgate:processing"
}

# Set failed label
set_failed_label() {
    local repo="$1"
    local issue="$2"

    update_issue_label "$repo" "$issue" "flowgate:processing" "flowgate:failed"
    log_task "$repo" "$issue" "INFO" "Label changed: flowgate:processing -> flowgate:failed"
}

# Set timeout label
set_timeout_label() {
    local repo="$1"
    local issue="$2"

    update_issue_label "$repo" "$issue" "flowgate:processing" "flowgate:timeout"
    log_task "$repo" "$issue" "INFO" "Label changed: flowgate:processing -> flowgate:timeout"
}

# Remove processing label on success
remove_processing_label() {
    local repo="$1"
    local issue="$2"

    update_issue_label "$repo" "$issue" "flowgate:processing" ""
    log_task "$repo" "$issue" "INFO" "Label removed: flowgate:processing"
}

# Rotate logs (keep only last N days)
rotate_logs() {
    local retention_days="${1:-30}"

    log_watcher "INFO" "Starting log rotation (retention: ${retention_days} days)"

    local count=0
    if [[ -d "$FLOWGATE_LOGS_DIR/tasks" ]]; then
        while IFS= read -r -d '' file; do
            rm -f "$file"
            ((count++))
        done < <(find "$FLOWGATE_LOGS_DIR/tasks" -name "*.log" -mtime +"$retention_days" -print0 2>/dev/null)
    fi

    log_watcher "INFO" "Log rotation complete (removed: $count files)"
}
