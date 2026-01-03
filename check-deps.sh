#!/usr/bin/env bash
set -euo pipefail

#
# flowgate check-deps.sh
# 依存関係のチェックスクリプト
#

# =============================================================================
# カラー定義
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# =============================================================================
# ヘルパー関数
# =============================================================================
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

error() {
    echo -e "${RED}[✗]${NC} $1"
}

header() {
    echo ""
    echo -e "${BOLD}$1${NC}"
    echo "$(echo "$1" | sed 's/./-/g')"
}

# コマンドの存在確認
command_exists() {
    command -v "$1" &> /dev/null
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

# =============================================================================
# OS判定
# =============================================================================
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

    info "OS: ${OS}, パッケージマネージャ: ${PKG_MANAGER}"
}

# =============================================================================
# インストール方法の提示
# =============================================================================
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

# =============================================================================
# 依存関係チェック
# =============================================================================

# チェック結果を記録
declare -A CHECK_RESULTS
declare -a MISSING_DEPS

# Git
check_git() {
    if command_exists git; then
        local version
        version=$(git --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
        success "git $version"
        CHECK_RESULTS["git"]="ok ($version)"
        return 0
    else
        error "git が見つかりません"
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
            success "Node.js v$version"
            CHECK_RESULTS["nodejs"]="ok (v$version)"
            return 0
        else
            error "Node.js v$version は古いです (v20+ が必要)"
            CHECK_RESULTS["nodejs"]="old version (v$version < v20)"
            MISSING_DEPS+=("node")
            show_install_instruction "node" "Node.js v20 以降が必要です"
            return 1
        fi
    else
        error "Node.js が見つかりません"
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
        success "gh CLI $version"
        CHECK_RESULTS["gh"]="ok ($version)"
        return 0
    else
        error "gh CLI が見つかりません"
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
        success "pueue $version"
        CHECK_RESULTS["pueue"]="ok ($version)"
        return 0
    else
        error "pueue が見つかりません"
        CHECK_RESULTS["pueue"]="missing"
        MISSING_DEPS+=("pueue")
        show_install_instruction "pueue" "タスクキュー管理ツール"
        return 1
    fi
}

# claude-flow (npm)
check_claude_flow() {
    if npm list -g @anthropic-ai/claude-flow &> /dev/null || command_exists claude-flow; then
        local version
        version=$(npm list -g @anthropic-ai/claude-flow 2>/dev/null | grep claude-flow | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "installed")
        success "claude-flow $version"
        CHECK_RESULTS["claude-flow"]="ok ($version)"
        return 0
    else
        error "claude-flow が見つかりません"
        CHECK_RESULTS["claude-flow"]="missing"
        MISSING_DEPS+=("claude-flow")
        show_install_instruction "claude-flow" "Claude Flow CLI"
        return 1
    fi
}

# claude code (npm: @anthropic-ai/claude-code)
check_claude_code() {
    if npm list -g @anthropic-ai/claude-code &> /dev/null || command_exists claude; then
        local version
        version=$(npm list -g @anthropic-ai/claude-code 2>/dev/null | grep claude-code | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "installed")
        success "claude-code $version"
        CHECK_RESULTS["claude-code"]="ok ($version)"
        return 0
    else
        error "claude-code が見つかりません"
        CHECK_RESULTS["claude-code"]="missing"
        MISSING_DEPS+=("claude-code")
        show_install_instruction "claude-code" "Claude Code CLI"
        return 1
    fi
}

# =============================================================================
# サマリー表示
# =============================================================================
show_summary() {
    header "依存関係チェック結果"

    local all_ok=true

    for dep in git nodejs gh pueue claude-flow claude-code; do
        local status="${CHECK_RESULTS[$dep]:-unknown}"
        if [[ "$status" == "missing" ]] || [[ "$status" == old* ]]; then
            echo -e "  ${RED}✗${NC} $dep: $status"
            all_ok=false
        elif [[ "$status" == ok* ]]; then
            echo -e "  ${GREEN}✓${NC} $dep: $status"
        else
            echo -e "  ${BLUE}•${NC} $dep: $status"
        fi
    done

    echo ""

    if [[ "$all_ok" == false ]]; then
        error "${#MISSING_DEPS[@]} 個の依存関係が不足しています"
        echo ""
        echo "上記のインストール方法を参考に、必要な依存関係をインストールしてください。"
        echo "すべての依存関係がインストールされたら、再度このスクリプトを実行してください。"
        exit 1
    else
        success "すべての依存関係が揃っています"
        echo ""
        echo -e "${BOLD}次のステップ:${NC}"
        echo "  ./init.sh    # 初期設定と認証"
    fi
}

# =============================================================================
# メイン処理
# =============================================================================
main() {
    echo ""
    echo -e "${BOLD}flowgate 依存関係チェッカー${NC}"
    echo "=============================="
    echo ""

    # OS判定
    detect_os

    # 依存関係チェック
    header "依存関係のチェック"

    check_git
    check_nodejs
    check_gh
    check_pueue
    check_claude_flow
    check_claude_code

    # サマリー表示
    show_summary
}

# スクリプト実行
main "$@"
