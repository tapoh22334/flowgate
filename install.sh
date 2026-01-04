#!/usr/bin/env bash
set -euo pipefail

#=============================================================================
# flowgate install.sh - 統合インストールスクリプト
# 依存関係チェック + 初期設定 + systemdサービスインストール
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
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly FLOWGATE_DIR="${HOME}/.flowgate"
readonly CONFIG_FILE="${FLOWGATE_DIR}/config.toml"
readonly REPOS_META="${FLOWGATE_DIR}/repos.meta"
readonly LOGS_DIR="${FLOWGATE_DIR}/logs"
readonly REPOS_DIR="${FLOWGATE_DIR}/repos"
readonly BIN_DIR="${HOME}/.local/bin"
readonly SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"

# pueueグループ名
readonly PUEUE_GROUP="flowgate"

# チェック結果を記録
declare -A CHECK_RESULTS
declare -a MISSING_DEPS

#=============================================================================
# ユーティリティ関数
#=============================================================================

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}flowgate installer${NC}"
    echo -e "${CYAN}==================${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BOLD}${BLUE}$1${NC}"
    echo -e "${BLUE}$(echo "$1" | sed 's/./-/g')${NC}"
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

print_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

confirm_prompt() {
    local message="$1"
    local response
    echo -en "${YELLOW}${message} [y/N]:${NC} "
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

command_exists() {
    command -v "$1" &>/dev/null
}

# バージョン比較（major.minor形式）
version_gte() {
    local current="$1"
    local required="$2"

    local current_major current_minor required_major required_minor
    current_major=$(echo "$current" | cut -d. -f1)
    current_minor=$(echo "$current" | cut -d. -f2)
    required_major=$(echo "$required" | cut -d. -f1)
    required_minor=$(echo "$required" | cut -d. -f2)

    if [[ "$current_major" -gt "$required_major" ]]; then
        return 0
    elif [[ "$current_major" -eq "$required_major" && "$current_minor" -ge "$required_minor" ]]; then
        return 0
    else
        return 1
    fi
}

#=============================================================================
# OS判定
#=============================================================================
detect_os() {
    case "$(uname -s)" in
        Darwin*)
            OS="macos"
            PKG_MANAGER="brew"
            ;;
        Linux*)
            OS="linux"
            if command_exists apt-get; then
                PKG_MANAGER="apt-get"
            elif command_exists dnf; then
                PKG_MANAGER="dnf"
            elif command_exists yum; then
                PKG_MANAGER="yum"
            elif command_exists pacman; then
                PKG_MANAGER="pacman"
            else
                PKG_MANAGER="unknown"
            fi
            ;;
        *)
            OS="unknown"
            PKG_MANAGER="unknown"
            ;;
    esac

    print_info "OS: ${OS}, パッケージマネージャ: ${PKG_MANAGER}"
}

#=============================================================================
# インストール方法の提示
#=============================================================================
show_install_instruction() {
    local tool="$1"
    local desc="$2"

    echo ""
    echo -e "${YELLOW}${tool} が見つかりません${NC}"
    echo -e "  ${desc}"
    echo ""
    echo "インストール方法:"

    case "$tool" in
        git)
            case "$PKG_MANAGER" in
                brew) echo "  brew install git" ;;
                apt-get) echo "  sudo apt-get install git" ;;
                dnf|yum) echo "  sudo $PKG_MANAGER install git" ;;
                pacman) echo "  sudo pacman -S git" ;;
                *) echo "  公式サイト: https://git-scm.com/downloads" ;;
            esac
            ;;
        node)
            case "$PKG_MANAGER" in
                brew) echo "  brew install node@20" ;;
                apt-get)
                    echo "  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -"
                    echo "  sudo apt-get install -y nodejs"
                    ;;
                dnf|yum)
                    echo "  curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -"
                    echo "  sudo $PKG_MANAGER install -y nodejs"
                    ;;
                pacman) echo "  sudo pacman -S nodejs npm" ;;
                *) echo "  公式サイト: https://nodejs.org/" ;;
            esac
            ;;
        gh)
            case "$PKG_MANAGER" in
                brew) echo "  brew install gh" ;;
                apt-get)
                    echo "  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg"
                    echo "  echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null"
                    echo "  sudo apt-get update && sudo apt-get install gh"
                    ;;
                dnf)
                    echo "  sudo dnf install 'dnf-command(config-manager)'"
                    echo "  sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo"
                    echo "  sudo dnf install gh"
                    ;;
                yum)
                    echo "  sudo yum-config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo"
                    echo "  sudo yum install gh"
                    ;;
                pacman) echo "  sudo pacman -S github-cli" ;;
                *) echo "  公式サイト: https://cli.github.com/" ;;
            esac
            ;;
        pueue)
            case "$PKG_MANAGER" in
                brew) echo "  brew install pueue" ;;
                pacman) echo "  sudo pacman -S pueue" ;;
                *)
                    echo "  cargo install pueue"
                    echo "  または公式サイト: https://github.com/Nukesor/pueue"
                    ;;
            esac
            ;;
        claude-flow)
            echo "  npm install -g @anthropic-ai/claude-flow@alpha"
            ;;
        claude-code)
            echo "  npm install -g @anthropic-ai/claude-code"
            ;;
    esac
}

#=============================================================================
# 依存関係チェック
#=============================================================================

# Git
check_git() {
    if command_exists git; then
        local version
        version=$(git --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
        print_success "git $version"
        CHECK_RESULTS["git"]="ok ($version)"
        return 0
    else
        print_fail "git が見つかりません"
        CHECK_RESULTS["git"]="missing"
        MISSING_DEPS+=("git")
        show_install_instruction "git" "バージョン管理システム"
        return 1
    fi
}

# Node.js (20+)
check_nodejs() {
    if command_exists node; then
        local version
        version=$(node --version | tr -d 'v' | cut -d. -f1-2)
        if version_gte "$version" "20.0"; then
            print_success "Node.js v$version"
            CHECK_RESULTS["nodejs"]="ok (v$version)"
            return 0
        else
            print_fail "Node.js v$version は古いです (v20+ が必要)"
            CHECK_RESULTS["nodejs"]="old version (v$version < v20)"
            MISSING_DEPS+=("node")
            show_install_instruction "node" "Node.js v20 以降が必要です"
            return 1
        fi
    else
        print_fail "Node.js が見つかりません"
        CHECK_RESULTS["nodejs"]="missing"
        MISSING_DEPS+=("node")
        show_install_instruction "node" "JavaScript ランタイム (v20+ が必要)"
        return 1
    fi
}

# gh CLI
check_gh() {
    if command_exists gh; then
        local version
        version=$(gh --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        print_success "gh CLI $version"
        CHECK_RESULTS["gh"]="ok ($version)"
        return 0
    else
        print_fail "gh CLI が見つかりません"
        CHECK_RESULTS["gh"]="missing"
        MISSING_DEPS+=("gh")
        show_install_instruction "gh" "GitHub CLI"
        return 1
    fi
}

# pueue
check_pueue() {
    if command_exists pueue && command_exists pueued; then
        local version
        version=$(pueue --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        print_success "pueue $version"
        CHECK_RESULTS["pueue"]="ok ($version)"
        return 0
    else
        print_fail "pueue が見つかりません"
        CHECK_RESULTS["pueue"]="missing"
        MISSING_DEPS+=("pueue")
        show_install_instruction "pueue" "タスクキュー管理ツール"
        return 1
    fi
}

# claude-flow (npm)
check_claude_flow() {
    if npm list -g @anthropic-ai/claude-flow &>/dev/null || command_exists claude-flow; then
        local version
        version=$(npm list -g @anthropic-ai/claude-flow 2>/dev/null | grep claude-flow | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "installed")
        print_success "claude-flow $version"
        CHECK_RESULTS["claude-flow"]="ok ($version)"
        return 0
    else
        print_fail "claude-flow が見つかりません"
        CHECK_RESULTS["claude-flow"]="missing"
        MISSING_DEPS+=("claude-flow")
        show_install_instruction "claude-flow" "Claude Flow CLI"
        return 1
    fi
}

# claude code (npm: @anthropic-ai/claude-code)
check_claude_code() {
    if npm list -g @anthropic-ai/claude-code &>/dev/null || command_exists claude; then
        local version
        version=$(npm list -g @anthropic-ai/claude-code 2>/dev/null | grep claude-code | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "installed")
        print_success "claude-code $version"
        CHECK_RESULTS["claude-code"]="ok ($version)"
        return 0
    else
        print_fail "claude-code が見つかりません"
        CHECK_RESULTS["claude-code"]="missing"
        MISSING_DEPS+=("claude-code")
        show_install_instruction "claude-code" "Claude Code CLI"
        return 1
    fi
}

check_all_dependencies() {
    print_section "1. 依存関係のチェック"

    detect_os
    echo ""

    local all_ok=true

    check_git || all_ok=false
    check_nodejs || all_ok=false
    check_gh || all_ok=false
    check_pueue || all_ok=false
    check_claude_flow || all_ok=false
    check_claude_code || all_ok=false

    echo ""

    if [[ "$all_ok" == false ]]; then
        print_error "${#MISSING_DEPS[@]} 個の依存関係が不足しています"
        echo ""
        echo "上記のインストール方法を参考に、必要な依存関係をインストールしてください。"
        echo "すべての依存関係がインストールされたら、再度このスクリプトを実行してください。"
        exit 1
    else
        print_success "すべての依存関係が揃っています"
    fi
}

#=============================================================================
# 認証
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

run_authentication() {
    print_section "2. 認証"

    do_github_auth
    echo ""

    do_claude_auth
}

#=============================================================================
# pueued セットアップ
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

setup_pueue() {
    print_section "3. pueue セットアップ"

    start_pueued
    echo ""

    create_pueue_group
}

#=============================================================================
# ディレクトリ構造作成
#=============================================================================

create_directory_structure() {
    print_section "4. ディレクトリ構造の作成"

    print_step "Creating directories..."

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

    # ~/.local/bin ディレクトリ
    if [[ ! -d "$BIN_DIR" ]]; then
        mkdir -p "$BIN_DIR"
        print_success "Created ${BIN_DIR}"
    else
        print_success "${BIN_DIR} exists"
    fi

    # config.toml（存在しない場合のみ作成）
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'EOF'
# flowgate configuration
mode = "swarm"          # デフォルト実行モード: swarm | hive
group = "flowgate"      # pueueグループ名
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
# スクリプトインストール
#=============================================================================

install_scripts() {
    print_section "5. スクリプトのインストール"

    print_step "Installing flowgate scripts to ${BIN_DIR}..."

    # flowgate.sh を flowgate としてインストール
    if [[ -f "${SCRIPT_DIR}/scripts/flowgate.sh" ]]; then
        cp "${SCRIPT_DIR}/scripts/flowgate.sh" "${BIN_DIR}/flowgate"
        chmod +x "${BIN_DIR}/flowgate"
        print_success "Installed flowgate"
    else
        print_fail "scripts/flowgate.sh not found"
        return 1
    fi

    # flowgate-watcher.sh をインストール
    if [[ -f "${SCRIPT_DIR}/scripts/flowgate-watcher.sh" ]]; then
        cp "${SCRIPT_DIR}/scripts/flowgate-watcher.sh" "${BIN_DIR}/flowgate-watcher"
        chmod +x "${BIN_DIR}/flowgate-watcher"
        print_success "Installed flowgate-watcher"
    else
        print_fail "scripts/flowgate-watcher.sh not found"
        return 1
    fi

    # PATHチェック
    if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
        echo ""
        print_warn "${BIN_DIR} is not in your PATH"
        print_info "Add this to your ~/.bashrc or ~/.zshrc:"
        echo ""
        echo "  export PATH=\"\${HOME}/.local/bin:\${PATH}\""
        echo ""
    fi
}

#=============================================================================
# systemd サービスインストール
#=============================================================================

install_systemd_service() {
    print_section "6. systemd サービスのインストール"

    print_step "Installing systemd units..."

    # systemdユーザーディレクトリを作成
    if [[ ! -d "$SYSTEMD_USER_DIR" ]]; then
        mkdir -p "$SYSTEMD_USER_DIR"
        print_success "Created ${SYSTEMD_USER_DIR}"
    fi

    # ユニットファイルをコピー
    if [[ -f "${SCRIPT_DIR}/systemd/flowgate.service" ]]; then
        cp "${SCRIPT_DIR}/systemd/flowgate.service" "$SYSTEMD_USER_DIR/"
        print_success "Installed flowgate.service"
    else
        print_fail "systemd/flowgate.service not found"
        return 1
    fi

    if [[ -f "${SCRIPT_DIR}/systemd/flowgate.timer" ]]; then
        cp "${SCRIPT_DIR}/systemd/flowgate.timer" "$SYSTEMD_USER_DIR/"
        print_success "Installed flowgate.timer"
    else
        print_fail "systemd/flowgate.timer not found"
        return 1
    fi

    # daemon-reload
    print_step "Reloading systemd daemon..."
    if systemctl --user daemon-reload; then
        print_success "systemd daemon reloaded"
    else
        print_fail "Failed to reload systemd daemon"
        return 1
    fi

    echo ""

    # タイマーを有効化するか確認
    if confirm_prompt "Enable and start flowgate.timer now?"; then
        if systemctl --user enable --now flowgate.timer; then
            print_success "flowgate.timer enabled and started"
            echo ""
            print_info "Check status with:"
            echo "  systemctl --user status flowgate.timer"
            echo "  systemctl --user list-timers"
        else
            print_fail "Failed to enable flowgate.timer"
            return 1
        fi
    else
        print_info "To enable later, run:"
        echo "  systemctl --user enable --now flowgate.timer"
    fi
}

#=============================================================================
# 完了メッセージ
#=============================================================================

print_completion() {
    echo ""
    echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}${BOLD}  Installation complete!${NC}"
    echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}Next steps:${NC}"
    echo ""
    echo "  1. Add a repository to watch:"
    echo "     ${CYAN}flowgate repo add owner/repo${NC}"
    echo ""
    echo "  2. (Optional) Check timer status:"
    echo "     ${CYAN}systemctl --user status flowgate.timer${NC}"
    echo "     ${CYAN}systemctl --user list-timers${NC}"
    echo ""
    echo "  3. View logs:"
    echo "     ${CYAN}journalctl --user -u flowgate -f${NC}"
    echo "     ${CYAN}tail -f ~/.flowgate/logs/watcher.log${NC}"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo "  Add 'flowgate' label to any GitHub Issue in your watched repos"
    echo "  flowgate will automatically create a PR within 1 minute"
    echo ""
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
            *)
                print_error "Unknown option: $1"
                echo "Usage: ./install.sh [--reauth]"
                exit 1
                ;;
        esac
    done

    export REAUTH

    # ヘッダー表示
    print_header

    # 1. 依存関係チェック
    check_all_dependencies

    # 2. 認証
    run_authentication

    # 3. pueueセットアップ
    setup_pueue

    # 4. ディレクトリ構造作成
    create_directory_structure

    # 5. スクリプトインストール
    install_scripts

    # 6. systemdサービスインストール
    install_systemd_service

    # 完了メッセージ
    print_completion
}

# スクリプト実行
main "$@"
