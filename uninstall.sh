#!/usr/bin/env bash
set -euo pipefail

#=============================================================================
# flowgate uninstall.sh - アンインストールスクリプト
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
readonly BIN_DIR="${HOME}/.local/bin"
readonly SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"

# pueueグループ名
readonly PUEUE_GROUP="flowgate"

#=============================================================================
# ユーティリティ関数
#=============================================================================

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}flowgate uninstaller${NC}"
    echo -e "${CYAN}=====================${NC}"
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

print_fail() {
    echo -e "  ${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "  ${BLUE}$1${NC}"
}

print_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
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
# systemd サービスのアンインストール
#=============================================================================

uninstall_systemd_service() {
    print_section "1. systemd サービスの削除"

    local timer_active=false
    local service_exists=false

    # タイマーが有効か確認
    if systemctl --user is-enabled flowgate.timer &>/dev/null; then
        timer_active=true
    fi

    # サービスファイルが存在するか確認
    if [[ -f "${SYSTEMD_USER_DIR}/flowgate.timer" ]] || [[ -f "${SYSTEMD_USER_DIR}/flowgate.service" ]]; then
        service_exists=true
    fi

    if [[ "$timer_active" == true ]]; then
        print_step "Stopping and disabling flowgate.timer..."
        if systemctl --user stop flowgate.timer 2>/dev/null; then
            print_success "Stopped flowgate.timer"
        fi
        if systemctl --user disable flowgate.timer 2>/dev/null; then
            print_success "Disabled flowgate.timer"
        fi
    else
        print_info "flowgate.timer is not enabled"
    fi

    # サービスファイルを削除
    if [[ "$service_exists" == true ]]; then
        print_step "Removing systemd unit files..."

        if [[ -f "${SYSTEMD_USER_DIR}/flowgate.timer" ]]; then
            rm -f "${SYSTEMD_USER_DIR}/flowgate.timer"
            print_success "Removed flowgate.timer"
        fi

        if [[ -f "${SYSTEMD_USER_DIR}/flowgate.service" ]]; then
            rm -f "${SYSTEMD_USER_DIR}/flowgate.service"
            print_success "Removed flowgate.service"
        fi

        # daemon-reload
        if systemctl --user daemon-reload 2>/dev/null; then
            print_success "systemd daemon reloaded"
        fi
    else
        print_info "No systemd unit files found"
    fi
}

#=============================================================================
# スクリプトのアンインストール
#=============================================================================

uninstall_scripts() {
    print_section "2. スクリプトの削除"

    print_step "Removing flowgate scripts from ${BIN_DIR}..."

    local removed=false

    if [[ -f "${BIN_DIR}/flowgate" ]]; then
        rm -f "${BIN_DIR}/flowgate"
        print_success "Removed flowgate"
        removed=true
    fi

    if [[ -f "${BIN_DIR}/flowgate-watcher" ]]; then
        rm -f "${BIN_DIR}/flowgate-watcher"
        print_success "Removed flowgate-watcher"
        removed=true
    fi

    if [[ "$removed" == false ]]; then
        print_info "No scripts found in ${BIN_DIR}"
    fi
}

#=============================================================================
# pueue グループの削除
#=============================================================================

remove_pueue_group() {
    print_section "3. pueue グループの削除"

    # pueueが利用可能か確認
    if ! command -v pueue &>/dev/null; then
        print_info "pueue not found, skipping group removal"
        return 0
    fi

    # pueuedが起動しているか確認
    if ! pueue status &>/dev/null 2>&1; then
        print_info "pueued not running, skipping group removal"
        return 0
    fi

    print_step "Checking for flowgate group..."

    if pueue group | grep -q "^${PUEUE_GROUP}" 2>/dev/null; then
        # グループ内のタスクを確認
        local task_count
        task_count=$(pueue status --group "$PUEUE_GROUP" 2>/dev/null | grep -c "^[0-9]" || echo "0")

        if [[ "$task_count" -gt 0 ]]; then
            print_warn "Found $task_count task(s) in '${PUEUE_GROUP}' group"

            if confirm_prompt "Remove all tasks and delete the group?"; then
                # すべてのタスクを削除
                pueue clean --group "$PUEUE_GROUP" 2>/dev/null || true
                pueue remove --group "$PUEUE_GROUP" $(pueue status --group "$PUEUE_GROUP" -j | grep -oP '"id":\K\d+' 2>/dev/null || echo "") 2>/dev/null || true
            else
                print_info "Keeping pueue group '${PUEUE_GROUP}'"
                return 0
            fi
        fi

        # グループを削除
        if pueue group remove "$PUEUE_GROUP" &>/dev/null; then
            print_success "Removed pueue group '${PUEUE_GROUP}'"
        else
            print_fail "Failed to remove pueue group '${PUEUE_GROUP}'"
        fi
    else
        print_info "Group '${PUEUE_GROUP}' not found"
    fi
}

#=============================================================================
# データディレクトリの削除
#=============================================================================

remove_data_directory() {
    print_section "4. データディレクトリの削除"

    if [[ ! -d "$FLOWGATE_DIR" ]]; then
        print_info "${FLOWGATE_DIR} does not exist"
        return 0
    fi

    # ディレクトリのサイズを確認
    local dir_size
    dir_size=$(du -sh "$FLOWGATE_DIR" 2>/dev/null | cut -f1 || echo "unknown")

    echo ""
    print_warn "This will permanently delete:"
    echo "  - Configuration: ${FLOWGATE_DIR}/config.toml"
    echo "  - Repository list: ${FLOWGATE_DIR}/repos.meta"
    echo "  - Logs: ${FLOWGATE_DIR}/logs/"
    echo "  - Cloned repositories: ${FLOWGATE_DIR}/repos/"
    echo ""
    print_info "Total size: ${dir_size}"
    echo ""

    if confirm_prompt "Delete ${FLOWGATE_DIR}?"; then
        print_step "Removing ${FLOWGATE_DIR}..."

        if rm -rf "$FLOWGATE_DIR"; then
            print_success "Removed ${FLOWGATE_DIR}"
        else
            print_fail "Failed to remove ${FLOWGATE_DIR}"
            return 1
        fi
    else
        print_info "Keeping ${FLOWGATE_DIR}"
        echo ""
        print_info "To manually remove later:"
        echo "  rm -rf ${FLOWGATE_DIR}"
    fi
}

#=============================================================================
# 完了メッセージ
#=============================================================================

print_completion() {
    echo ""
    echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}${BOLD}  Uninstallation complete!${NC}"
    echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}flowgate has been removed from your system.${NC}"
    echo ""

    # データディレクトリが残っている場合は通知
    if [[ -d "$FLOWGATE_DIR" ]]; then
        echo "Note: Data directory ${FLOWGATE_DIR} was preserved."
        echo "To remove it manually:"
        echo "  rm -rf ${FLOWGATE_DIR}"
        echo ""
    fi
}

#=============================================================================
# ヘルプ表示
#=============================================================================

show_help() {
    cat << EOF
Usage: uninstall.sh [OPTIONS]

flowgate アンインストーラー

OPTIONS:
  -y, --yes   すべての確認をスキップ（自動的にyesと回答）
  -h, --help  このヘルプを表示

DESCRIPTION:
  flowgateを完全にアンインストールします：
  1. systemdサービスの停止と削除
  2. インストールされたスクリプトの削除
  3. pueueグループの削除
  4. データディレクトリの削除（確認あり）

EXAMPLES:
  # 対話的にアンインストール
  ./uninstall.sh

  # すべて自動削除（確認なし）
  ./uninstall.sh -y

EOF
}

#=============================================================================
# メイン処理
#=============================================================================

main() {
    local AUTO_YES=false

    # 引数解析
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes)
                AUTO_YES=true
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

    # ヘッダー表示
    print_header

    # 確認プロンプト（--yes でない場合）
    if [[ "$AUTO_YES" == false ]]; then
        echo -e "${BOLD}This will uninstall flowgate from your system.${NC}"
        echo ""
        if ! confirm_prompt "Continue?"; then
            echo "Aborted."
            exit 0
        fi
    fi

    # 1. systemdサービスのアンインストール
    uninstall_systemd_service

    # 2. スクリプトのアンインストール
    uninstall_scripts

    # 3. pueueグループの削除
    remove_pueue_group

    # 4. データディレクトリの削除
    if [[ "$AUTO_YES" == true ]]; then
        # --yes オプションの場合は自動削除
        print_section "4. データディレクトリの削除"
        print_step "Removing ${FLOWGATE_DIR}..."
        if [[ -d "$FLOWGATE_DIR" ]]; then
            rm -rf "$FLOWGATE_DIR"
            print_success "Removed ${FLOWGATE_DIR}"
        else
            print_info "${FLOWGATE_DIR} does not exist"
        fi
    else
        remove_data_directory
    fi

    # 完了メッセージ
    print_completion
}

# スクリプト実行
main "$@"
