#!/usr/bin/env bash
set -euo pipefail

#
# flowgate install.sh
# 依存関係チェックスクリプト（インストールは行いません）
#
# セキュリティ上の理由から、このスクリプトは依存関係のインストールを行いません。
# ユーザーは事前に必要な依存関係をインストールする必要があります。
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
    printf '%s\n' "${1//?/-}"
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
# 依存関係チェック（インストールなし）
# =============================================================================

# チェック結果を記録
declare -A CHECK_RESULTS

# Git
check_git() {
    if command_exists git; then
        local version
        version=$(git --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
        success "git $version"
        CHECK_RESULTS["git"]="OK ($version)"
        return 0
    else
        error "git がインストールされていません"
        CHECK_RESULTS["git"]="MISSING"
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
            CHECK_RESULTS["nodejs"]="OK (v$version)"
            return 0
        else
            error "Node.js v$version は古いです (v20+ 必要)"
            CHECK_RESULTS["nodejs"]="VERSION_OLD (v$version, need v20+)"
            return 1
        fi
    else
        error "Node.js がインストールされていません (v20+ 必要)"
        CHECK_RESULTS["nodejs"]="MISSING"
        return 1
    fi
}

# gh CLI
check_gh() {
    if command_exists gh; then
        local version
        version=$(gh --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        success "gh CLI $version"
        CHECK_RESULTS["gh"]="OK ($version)"
        return 0
    else
        error "gh CLI がインストールされていません"
        CHECK_RESULTS["gh"]="MISSING"
        return 1
    fi
}

# pueue
check_pueue() {
    if command_exists pueue && command_exists pueued; then
        local version
        version=$(pueue --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        success "pueue $version"
        CHECK_RESULTS["pueue"]="OK ($version)"
        return 0
    else
        error "pueue/pueued がインストールされていません"
        CHECK_RESULTS["pueue"]="MISSING"
        return 1
    fi
}

# claude-flow (npm)
check_claude_flow() {
    if npm list -g @anthropic-ai/claude-flow &> /dev/null || command_exists claude-flow; then
        local version
        version=$(npm list -g @anthropic-ai/claude-flow 2>/dev/null | grep claude-flow | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        success "claude-flow $version"
        CHECK_RESULTS["claude-flow"]="OK ($version)"
        return 0
    else
        error "claude-flow がインストールされていません"
        CHECK_RESULTS["claude-flow"]="MISSING"
        return 1
    fi
}

# claude code (npm: @anthropic-ai/claude-code)
check_claude_code() {
    if npm list -g @anthropic-ai/claude-code &> /dev/null || command_exists claude; then
        local version
        version=$(npm list -g @anthropic-ai/claude-code 2>/dev/null | grep claude-code | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        success "claude-code $version"
        CHECK_RESULTS["claude-code"]="OK ($version)"
        return 0
    else
        error "claude-code がインストールされていません"
        CHECK_RESULTS["claude-code"]="MISSING"
        return 1
    fi
}

# =============================================================================
# インストール手順を表示
# =============================================================================
show_install_instructions() {
    header "インストール手順"

    echo ""
    echo "以下の依存関係を手動でインストールしてください:"
    echo ""

    for dep in git nodejs gh pueue claude-flow claude-code; do
        local status="${CHECK_RESULTS[$dep]:-unknown}"
        if [[ "$status" == MISSING* ]] || [[ "$status" == VERSION_OLD* ]]; then
            case "$dep" in
                git)
                    echo -e "${BOLD}git:${NC}"
                    echo "  macOS:  brew install git"
                    echo "  Ubuntu: sudo apt-get install git"
                    echo "  Fedora: sudo dnf install git"
                    echo ""
                    ;;
                nodejs)
                    echo -e "${BOLD}Node.js 20+:${NC}"
                    echo "  macOS:  brew install node@20"
                    echo "  Ubuntu: curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt-get install -y nodejs"
                    echo "  Fedora: curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash - && sudo dnf install -y nodejs"
                    echo "  または: https://nodejs.org/ からダウンロード"
                    echo ""
                    ;;
                gh)
                    echo -e "${BOLD}GitHub CLI (gh):${NC}"
                    echo "  macOS:  brew install gh"
                    echo "  Ubuntu: https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
                    echo "  または: https://cli.github.com/"
                    echo ""
                    ;;
                pueue)
                    echo -e "${BOLD}pueue:${NC}"
                    echo "  macOS:  brew install pueue"
                    echo "  cargo:  cargo install pueue"
                    echo "  または: https://github.com/Nukesor/pueue/releases"
                    echo ""
                    ;;
                claude-flow)
                    echo -e "${BOLD}claude-flow:${NC}"
                    echo "  npm install -g @anthropic-ai/claude-flow"
                    echo ""
                    ;;
                claude-code)
                    echo -e "${BOLD}claude-code:${NC}"
                    echo "  npm install -g @anthropic-ai/claude-code"
                    echo ""
                    ;;
            esac
        fi
    done
}

# =============================================================================
# サマリー表示
# =============================================================================
show_summary() {
    header "依存関係チェック結果"

    local missing=0

    for dep in git nodejs gh pueue claude-flow claude-code; do
        local status="${CHECK_RESULTS[$dep]:-unknown}"
        if [[ "$status" == MISSING* ]] || [[ "$status" == VERSION_OLD* ]]; then
            echo -e "  ${RED}✗${NC} $dep: $status"
            ((missing++))
        else
            echo -e "  ${GREEN}✓${NC} $dep: $status"
        fi
    done

    echo ""

    if [[ $missing -gt 0 ]]; then
        error "$missing 個の依存関係が不足しています"
        show_install_instructions
        exit 1
    else
        success "すべての依存関係が利用可能です"
        echo ""
        echo -e "${BOLD}次のステップ:${NC}"
        echo "  gh auth login    # GitHub認証（未認証の場合）"
        echo "  ./init.sh        # 初期設定"
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
    echo "注意: このスクリプトは依存関係のチェックのみを行います。"
    echo "      インストールは行いません（セキュリティ上の理由）。"
    echo ""

    # 依存関係チェック
    header "依存関係のチェック"

    local errors=0

    check_git || ((errors++))
    check_nodejs || ((errors++))
    check_gh || ((errors++))
    check_pueue || ((errors++))
    check_claude_flow || ((errors++))
    check_claude_code || ((errors++))

    # サマリー表示
    show_summary
}

# スクリプト実行
main "$@"
