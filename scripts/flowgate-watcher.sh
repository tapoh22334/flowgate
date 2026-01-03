#!/usr/bin/env bash
set -euo pipefail

# flowgate-watcher.sh
# GitHub Issueを監視し、flowgateラベル付きのIssueをキューに追加する
# systemd timerから1分ごとに呼び出される

# ============================================================
# 設定
# ============================================================

FLOWGATE_DIR="${HOME}/.flowgate"
REPOS_META="${FLOWGATE_DIR}/repos.meta"
LOG_DIR="${FLOWGATE_DIR}/logs"
LOG_FILE="${LOG_DIR}/watcher.log"
CONFIG_FILE="${FLOWGATE_DIR}/config.toml"

# 検索対象ラベル
TRIGGER_LABELS=("flowgate" "flowgate:swarm" "flowgate:hive")
PROCESSING_LABEL="flowgate:processing"

# ============================================================
# ユーティリティ関数
# ============================================================

# ログ出力
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
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

# ラベルからモードを解析
parse_mode() {
    local label="$1"
    case "$label" in
        "flowgate:swarm")
            echo "swarm"
            ;;
        "flowgate:hive")
            echo "hive"
            ;;
        "flowgate")
            # デフォルトモードを設定ファイルから取得（なければswarm）
            if [[ -f "$CONFIG_FILE" ]]; then
                local mode
                mode=$(grep -E '^mode\s*=' "$CONFIG_FILE" 2>/dev/null | sed 's/.*=\s*"\([^"]*\)".*/\1/' || echo "swarm")
                if [[ -n "$mode" ]]; then
                    echo "$mode"
                else
                    echo "swarm"
                fi
            else
                echo "swarm"
            fi
            ;;
        *)
            echo "swarm"
            ;;
    esac
}

# Issueが既にprocessing中かチェック
is_processing() {
    local repo="$1"
    local issue_number="$2"

    local labels
    labels=$(gh issue view "$issue_number" --repo "$repo" --json labels -q '.labels[].name' 2>/dev/null || echo "")

    if echo "$labels" | grep -qF "$PROCESSING_LABEL"; then
        return 0  # processing中
    else
        return 1  # processing中でない
    fi
}

# ============================================================
# 初期化
# ============================================================

init() {
    # ログディレクトリの作成
    mkdir -p "${LOG_DIR}"

    # repos.metaの存在確認
    if [[ ! -f "$REPOS_META" ]]; then
        log_warn "repos.meta not found: ${REPOS_META}"
        log_info "No repositories to watch. Add repositories with: flowgate repo add <owner/repo>"
        exit 0
    fi

    # gh CLIの認証確認
    if ! gh auth status &>/dev/null; then
        log_error "GitHub CLI not authenticated. Run: gh auth login"
        exit 1
    fi
}

# ============================================================
# メイン処理
# ============================================================

process_issues() {
    local repo="$1"

    log_info "Checking repository: ${repo}"

    for label in "${TRIGGER_LABELS[@]}"; do
        log_info "  Searching for label: ${label}"

        # ラベル付きIssueを検索
        local issues
        issues=$(gh issue list --repo "$repo" --label "$label" --state open --json number -q '.[].number' 2>/dev/null || echo "")

        if [[ -z "$issues" ]]; then
            log_info "    No issues found with label: ${label}"
            continue
        fi

        # 各Issueを処理
        while IFS= read -r issue_number; do
            [[ -z "$issue_number" ]] && continue

            log_info "    Found issue #${issue_number}"

            # 重複実行防止: 既にprocessing中ならスキップ
            if is_processing "$repo" "$issue_number"; then
                log_warn "    Issue #${issue_number} is already processing. Skipping."
                continue
            fi

            # モードを解析
            local mode
            mode=$(parse_mode "$label")
            log_info "    Mode: ${mode}"

            # processingラベルを追加
            log_info "    Adding ${PROCESSING_LABEL} label..."
            if ! gh issue edit "$issue_number" --repo "$repo" --add-label "$PROCESSING_LABEL" 2>/dev/null; then
                log_error "    Failed to add ${PROCESSING_LABEL} label to issue #${issue_number}"
                continue
            fi

            # flowgate CLIでキューに追加
            log_info "    Adding to queue with flowgate CLI..."
            local flowgate_cmd
            flowgate_cmd="flowgate ${repo} -m ${mode} ${issue_number}"

            if ! $flowgate_cmd 2>&1 | tee -a "${LOG_FILE}"; then
                log_error "    Failed to queue issue #${issue_number}"
                # 失敗時はprocessingラベルを削除
                gh issue edit "$issue_number" --repo "$repo" --remove-label "$PROCESSING_LABEL" 2>/dev/null || true
                continue
            fi

            # 元のトリガーラベルを削除
            log_info "    Removing trigger label: ${label}"
            if ! gh issue edit "$issue_number" --repo "$repo" --remove-label "$label" 2>/dev/null; then
                log_warn "    Failed to remove label ${label} from issue #${issue_number}"
            fi

            log_info "    Successfully queued issue #${issue_number}"

        done <<< "$issues"
    done
}

main() {
    log_info "=========================================="
    log_info "flowgate-watcher started"
    log_info "=========================================="

    # 初期化
    init

    # 監視対象リポジトリを読み込み
    local repos
    repos=$(grep -v '^#' "$REPOS_META" | grep -v '^$' || echo "")

    if [[ -z "$repos" ]]; then
        log_warn "No repositories configured in ${REPOS_META}"
        exit 0
    fi

    # 各リポジトリを処理
    while IFS= read -r repo; do
        [[ -z "$repo" ]] && continue

        # リポジトリ名の検証（owner/repo形式）
        if [[ ! "$repo" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$ ]]; then
            log_warn "Invalid repository format: ${repo}. Skipping."
            continue
        fi

        process_issues "$repo"

    done <<< "$repos"

    log_info "flowgate-watcher completed"
    log_info "=========================================="
}

# ============================================================
# エントリーポイント
# ============================================================

main "$@"
