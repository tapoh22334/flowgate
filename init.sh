#!/usr/bin/env bash
set -euo pipefail

#=============================================================================
# flowgate init.sh - セットアップウィザード
#=============================================================================

# 色定義
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# ディレクトリ
readonly FLOWGATE_DIR="${HOME}/.flowgate"
readonly CONFIG_FILE="${FLOWGATE_DIR}/config.toml"
readonly REPOS_META="${FLOWGATE_DIR}/repos.meta"
readonly LOGS_DIR="${FLOWGATE_DIR}/logs"
readonly REPOS_DIR="${FLOWGATE_DIR}/repos"

# pueueグループ名
readonly PUEUE_GROUP="flowgate"

#=============================================================================
# ユーティリティ関数
#=============================================================================

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}flowgate setup${NC}"
    echo -e "${CYAN}==============${NC}"
    echo ""
}

print_step() {
    echo -e "${BOLD}→ $1${NC}"
}

print_success() {
    echo -e "  ${GREEN}[✓]${NC} $1"
}

print_pending() {
    echo -e "  ${YELLOW}[ ]${NC} $1"
}

print_fail() {
    echo -e "  ${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "  ${BLUE}$1${NC}"
}

print_error() {
    echo -e "${RED}Error: $1${NC}" >&2
}

confirm_prompt() {
    local message="$1"
    local response
    echo -en "${YELLOW}${message} [y/N]:${NC} "
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

#=============================================================================
# 依存関係チェック
#=============================================================================

check_command() {
    command -v "$1" &>/dev/null
}

check_dependencies() {
    local all_ok=true

    echo "Checking dependencies..."
    echo ""

    # git
    if check_command git; then
        print_success "git"
    else
        print_fail "git - not installed"
        all_ok=false
    fi

    # gh CLI
    if check_command gh; then
        print_success "gh CLI"
    else
        print_fail "gh CLI - not installed"
        all_ok=false
    fi

    # pueue
    if check_command pueue; then
        print_success "pueue"
    else
        print_fail "pueue - not installed"
        all_ok=false
    fi

    # pueued
    if check_command pueued; then
        print_success "pueued"
    else
        print_fail "pueued - not installed"
        all_ok=false
    fi

    # Node.js
    if check_command node; then
        local node_version
        node_version=$(node -v | sed 's/v//' | cut -d. -f1)
        if [[ "$node_version" -ge 20 ]]; then
            print_success "Node.js $(node -v)"
        else
            print_fail "Node.js $(node -v) - version 20+ required"
            all_ok=false
        fi
    else
        print_fail "Node.js - not installed"
        all_ok=false
    fi

    # npx (comes with npm)
    if check_command npx; then
        print_success "npx"
    else
        print_fail "npx - not installed"
        all_ok=false
    fi

    # claude-flow
    if npx claude-flow@alpha --version &>/dev/null 2>&1; then
        print_success "claude-flow"
    else
        print_pending "claude-flow - will be installed on first use"
    fi

    # claude (Claude Code CLI)
    if check_command claude; then
        print_success "claude (Claude Code)"
    else
        print_fail "claude (Claude Code) - not installed"
        all_ok=false
    fi

    echo ""

    if [[ "$all_ok" == false ]]; then
        print_error "Some dependencies are missing. Please run install.sh first."
        exit 1
    fi
}

#=============================================================================
# 認証チェック・実行
#=============================================================================

check_github_auth() {
    gh auth status &>/dev/null 2>&1
}

do_github_auth() {
    print_step "GitHub authentication..."

    if check_github_auth && [[ "${REAUTH:-false}" != "true" ]]; then
        print_success "Already authenticated"
        return 0
    fi

    print_info "Starting GitHub authentication..."
    echo ""

    if ! gh auth login; then
        print_fail "GitHub authentication failed"
        return 1
    fi

    if check_github_auth; then
        print_success "GitHub authenticated"
    else
        print_fail "GitHub authentication verification failed"
        return 1
    fi
}

check_claude_auth() {
    # Claude Code の認証状態を確認
    # claude --version が成功し、認証エラーが出ないことを確認
    claude --version &>/dev/null 2>&1
}

do_claude_auth() {
    print_step "Claude authentication..."

    if check_claude_auth && [[ "${REAUTH:-false}" != "true" ]]; then
        print_success "Claude Code available"
        # 実際の認証確認のためにシンプルなコマンドを実行してみる
        if claude -p "echo test" &>/dev/null 2>&1; then
            print_success "Claude authenticated"
            return 0
        fi
    fi

    print_info "Please ensure Claude Code is authenticated."
    print_info "If not authenticated, run: claude"
    print_info "and follow the authentication flow."
    echo ""

    if confirm_prompt "Is Claude Code authenticated?"; then
        print_success "Claude authentication confirmed"
        return 0
    else
        print_pending "Claude authentication skipped (configure later)"
        return 0
    fi
}

#=============================================================================
# pueued 起動
#=============================================================================

check_pueued_running() {
    pueue status &>/dev/null 2>&1
}

start_pueued() {
    print_step "Starting pueued..."

    if check_pueued_running; then
        print_success "pueued already running"
        return 0
    fi

    print_info "Starting pueued daemon..."

    # pueued をバックグラウンドで起動
    pueued --daemonize &>/dev/null 2>&1 || true

    # 起動待機
    local max_attempts=10
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if check_pueued_running; then
            print_success "pueued started"
            return 0
        fi
        sleep 0.5
        ((attempt++))
    done

    print_fail "Failed to start pueued"
    return 1
}

#=============================================================================
# pueue グループ作成
#=============================================================================

check_pueue_group() {
    pueue group | grep -q "^${PUEUE_GROUP}" 2>/dev/null
}

create_pueue_group() {
    print_step "Creating pueue group '${PUEUE_GROUP}'..."

    if check_pueue_group; then
        print_success "Group '${PUEUE_GROUP}' already exists"
        return 0
    fi

    if pueue group add "$PUEUE_GROUP" &>/dev/null; then
        print_success "Group '${PUEUE_GROUP}' created"

        # 並行実行数を1に設定
        pueue parallel 1 --group "$PUEUE_GROUP" &>/dev/null || true
        print_info "Parallel tasks set to 1"
    else
        print_fail "Failed to create group '${PUEUE_GROUP}'"
        return 1
    fi
}

#=============================================================================
# ディレクトリ構造作成
#=============================================================================

create_directory_structure() {
    print_step "Creating directory structure..."

    # メインディレクトリ
    if [[ ! -d "$FLOWGATE_DIR" ]]; then
        mkdir -p "$FLOWGATE_DIR"
        print_success "Created ${FLOWGATE_DIR}"
    else
        print_success "${FLOWGATE_DIR} exists"
    fi

    # logs ディレクトリ
    if [[ ! -d "$LOGS_DIR" ]]; then
        mkdir -p "${LOGS_DIR}/tasks"
        print_success "Created ${LOGS_DIR}"
    else
        print_success "${LOGS_DIR} exists"
    fi

    # repos ディレクトリ
    if [[ ! -d "$REPOS_DIR" ]]; then
        mkdir -p "$REPOS_DIR"
        print_success "Created ${REPOS_DIR}"
    else
        print_success "${REPOS_DIR} exists"
    fi

    # config.toml（存在しない場合のみ作成）
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'EOF'
[general]
mode = "swarm"          # デフォルトモード: swarm | hive
poll_interval = 60      # ポーリング間隔(秒)
timeout = 21600         # タイムアウト(秒) = 6時間

[pueue]
parallel = 1            # 並行実行数
group = "flowgate"      # pueueグループ名

[logs]
retention_days = 30     # ログ保持日数
EOF
        print_success "Created ${CONFIG_FILE}"
    else
        print_success "${CONFIG_FILE} exists"
    fi

    # repos.meta（存在しない場合のみ作成）
    if [[ ! -f "$REPOS_META" ]]; then
        touch "$REPOS_META"
        print_success "Created ${REPOS_META}"
    else
        print_success "${REPOS_META} exists"
    fi
}

#=============================================================================
# セットアップ完了メッセージ
#=============================================================================

print_completion() {
    echo ""
    echo -e "${GREEN}${BOLD}Setup complete!${NC}"
    echo ""
    echo -e "${BOLD}Next steps:${NC}"
    echo "  flowgate repo add owner/repo"
    echo "  systemctl --user enable --now flowgate.timer"
    echo ""
}

#=============================================================================
# ヘルプ表示
#=============================================================================

show_help() {
    cat << EOF
Usage: init.sh [OPTIONS]

flowgate セットアップウィザード

OPTIONS:
  --reauth    認証を再実行する
  -h, --help  このヘルプを表示

DESCRIPTION:
  flowgateの初期セットアップを行います：
  - 依存関係のチェック
  - GitHub認証
  - Claude認証確認
  - pueuedの起動
  - flowgateグループの作成
  - ディレクトリ構造の作成

EOF
}

#=============================================================================
# メイン処理
#=============================================================================

main() {
    local REAUTH=false

    # 引数解析
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reauth)
                REAUTH=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    export REAUTH

    # ヘッダー表示
    print_header

    # 依存関係チェック
    check_dependencies

    # GitHub認証
    do_github_auth
    echo ""

    # Claude認証
    do_claude_auth
    echo ""

    # pueued起動
    start_pueued
    echo ""

    # pueueグループ作成
    create_pueue_group
    echo ""

    # ディレクトリ構造作成
    create_directory_structure

    # 完了メッセージ
    print_completion
}

# スクリプト実行
main "$@"
