#!/usr/bin/env bash
set -euo pipefail

#
# flowgate install.sh
# 依存関係のインストールスクリプト
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
            if ! command_exists brew; then
                error "Homebrew がインストールされていません"
                echo "  インストール: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                exit 1
            fi
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
                error "サポートされているパッケージマネージャが見つかりません (apt-get, dnf, yum, pacman)"
                exit 1
            fi
            ;;
        *)
            error "サポートされていないOS: $(uname -s)"
            exit 1
            ;;
    esac

    info "OS: ${OS}, パッケージマネージャ: ${PKG_MANAGER}"
}

# =============================================================================
# 依存関係チェック・インストール
# =============================================================================

# インストール結果を記録
declare -A INSTALL_RESULTS

# パッケージインストール
install_package() {
    local package="$1"
    local brew_name="${2:-$1}"

    case "$PKG_MANAGER" in
        brew)
            brew install "$brew_name"
            ;;
        apt-get)
            sudo apt-get update -qq
            sudo apt-get install -y "$package"
            ;;
        dnf|yum)
            sudo "$PKG_MANAGER" install -y "$package"
            ;;
        pacman)
            sudo pacman -S --noconfirm "$package"
            ;;
    esac
}

# Git
check_git() {
    if command_exists git; then
        local version
        version=$(git --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
        success "git $version"
        INSTALL_RESULTS["git"]="already installed ($version)"
        return 0
    else
        warn "git がインストールされていません。インストールします..."
        install_package git
        if command_exists git; then
            success "git をインストールしました"
            INSTALL_RESULTS["git"]="installed"
            return 0
        else
            error "git のインストールに失敗しました"
            INSTALL_RESULTS["git"]="FAILED"
            return 1
        fi
    fi
}

# Node.js (20+)
check_nodejs() {
    if command_exists node; then
        local version
        version=$(node --version | tr -d 'v' | cut -d. -f1-2)
        if version_gte "$version" "20.0"; then
            success "Node.js v$version"
            INSTALL_RESULTS["nodejs"]="already installed (v$version)"
            return 0
        else
            warn "Node.js v$version は古いです (v20+ 必要)"
        fi
    fi

    warn "Node.js 20+ がインストールされていません。インストールします..."

    case "$PKG_MANAGER" in
        brew)
            brew install node@20
            # node@20 のパスを通す（keg-only の場合）
            if [[ -d "/opt/homebrew/opt/node@20/bin" ]]; then
                export PATH="/opt/homebrew/opt/node@20/bin:$PATH"
            elif [[ -d "/usr/local/opt/node@20/bin" ]]; then
                export PATH="/usr/local/opt/node@20/bin:$PATH"
            fi
            ;;
        apt-get)
            # NodeSource を使用
            if ! command_exists curl; then
                sudo apt-get update -qq
                sudo apt-get install -y curl
            fi
            curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
            sudo apt-get install -y nodejs
            ;;
        dnf|yum)
            curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
            sudo "$PKG_MANAGER" install -y nodejs
            ;;
        pacman)
            sudo pacman -S --noconfirm nodejs npm
            ;;
    esac

    if command_exists node; then
        local version
        version=$(node --version)
        success "Node.js $version をインストールしました"
        INSTALL_RESULTS["nodejs"]="installed ($version)"
        return 0
    else
        error "Node.js のインストールに失敗しました"
        INSTALL_RESULTS["nodejs"]="FAILED"
        return 1
    fi
}

# gh CLI
check_gh() {
    if command_exists gh; then
        local version
        version=$(gh --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        success "gh CLI $version"
        INSTALL_RESULTS["gh"]="already installed ($version)"
        return 0
    fi

    warn "gh CLI がインストールされていません。インストールします..."

    case "$PKG_MANAGER" in
        brew)
            brew install gh
            ;;
        apt-get)
            # 公式リポジトリを追加
            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
            sudo apt-get update -qq
            sudo apt-get install -y gh
            ;;
        dnf)
            sudo dnf install -y 'dnf-command(config-manager)'
            sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
            sudo dnf install -y gh
            ;;
        yum)
            sudo yum-config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
            sudo yum install -y gh
            ;;
        pacman)
            sudo pacman -S --noconfirm github-cli
            ;;
    esac

    if command_exists gh; then
        success "gh CLI をインストールしました"
        INSTALL_RESULTS["gh"]="installed"
        return 0
    else
        error "gh CLI のインストールに失敗しました"
        INSTALL_RESULTS["gh"]="FAILED"
        return 1
    fi
}

# pueue
check_pueue() {
    if command_exists pueue && command_exists pueued; then
        local version
        version=$(pueue --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        success "pueue $version"
        INSTALL_RESULTS["pueue"]="already installed ($version)"
        return 0
    fi

    warn "pueue がインストールされていません。インストールします..."

    case "$PKG_MANAGER" in
        brew)
            brew install pueue
            ;;
        apt-get)
            # Cargo経由でインストール（aptにパッケージがないため）
            if ! command_exists cargo; then
                warn "Rust/Cargo をインストールします..."
                curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
                source "$HOME/.cargo/env"
            fi
            cargo install pueue
            ;;
        dnf|yum)
            if ! command_exists cargo; then
                warn "Rust/Cargo をインストールします..."
                curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
                source "$HOME/.cargo/env"
            fi
            cargo install pueue
            ;;
        pacman)
            sudo pacman -S --noconfirm pueue
            ;;
    esac

    # Cargo経由の場合、パスを再読み込み
    if [[ -f "$HOME/.cargo/env" ]]; then
        source "$HOME/.cargo/env"
    fi

    if command_exists pueue && command_exists pueued; then
        success "pueue をインストールしました"
        INSTALL_RESULTS["pueue"]="installed"
        return 0
    else
        error "pueue のインストールに失敗しました"
        INSTALL_RESULTS["pueue"]="FAILED"
        return 1
    fi
}

# claude-flow (npm)
check_claude_flow() {
    if npm list -g @anthropic-ai/claude-flow &> /dev/null || command_exists claude-flow; then
        local version
        version=$(npm list -g @anthropic-ai/claude-flow 2>/dev/null | grep claude-flow | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        success "claude-flow $version"
        INSTALL_RESULTS["claude-flow"]="already installed ($version)"
        return 0
    fi

    warn "claude-flow がインストールされていません。インストールします..."

    npm install -g @anthropic-ai/claude-flow@alpha

    if npm list -g @anthropic-ai/claude-flow &> /dev/null || command_exists claude-flow; then
        success "claude-flow をインストールしました"
        INSTALL_RESULTS["claude-flow"]="installed"
        return 0
    else
        error "claude-flow のインストールに失敗しました"
        INSTALL_RESULTS["claude-flow"]="FAILED"
        return 1
    fi
}

# claude code (npm: @anthropic-ai/claude-code)
check_claude_code() {
    if npm list -g @anthropic-ai/claude-code &> /dev/null || command_exists claude; then
        local version
        version=$(npm list -g @anthropic-ai/claude-code 2>/dev/null | grep claude-code | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        success "claude-code $version"
        INSTALL_RESULTS["claude-code"]="already installed ($version)"
        return 0
    fi

    warn "claude-code がインストールされていません。インストールします..."

    npm install -g @anthropic-ai/claude-code

    if npm list -g @anthropic-ai/claude-code &> /dev/null || command_exists claude; then
        success "claude-code をインストールしました"
        INSTALL_RESULTS["claude-code"]="installed"
        return 0
    else
        error "claude-code のインストールに失敗しました"
        INSTALL_RESULTS["claude-code"]="FAILED"
        return 1
    fi
}

# =============================================================================
# サマリー表示
# =============================================================================
show_summary() {
    header "インストール結果サマリー"

    local failed=0

    for dep in git nodejs gh pueue claude-flow claude-code; do
        local status="${INSTALL_RESULTS[$dep]:-unknown}"
        if [[ "$status" == "FAILED" ]]; then
            echo -e "  ${RED}✗${NC} $dep: $status"
            ((failed++))
        elif [[ "$status" == installed* ]]; then
            echo -e "  ${GREEN}✓${NC} $dep: $status"
        else
            echo -e "  ${BLUE}•${NC} $dep: $status"
        fi
    done

    echo ""

    if [[ $failed -gt 0 ]]; then
        error "$failed 個の依存関係のインストールに失敗しました"
        echo ""
        echo "手動でインストールしてから再実行してください。"
        exit 1
    else
        success "すべての依存関係がインストールされました"
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
    echo -e "${BOLD}flowgate インストーラー${NC}"
    echo "========================"
    echo ""

    # OS判定
    detect_os

    # 依存関係チェック・インストール
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
