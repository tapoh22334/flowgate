#!/bin/bash
# config.sh - TOML設定ファイル処理ライブラリ
#
# flowgate用の設定ファイル管理関数
# 純粋なbash + grep/sedでTOMLをパース

set -euo pipefail

# デフォルトパス
FLOWGATE_CONFIG_DIR="${FLOWGATE_CONFIG_DIR:-$HOME/.flowgate}"
FLOWGATE_CONFIG_FILE="${FLOWGATE_CONFIG_FILE:-$FLOWGATE_CONFIG_DIR/config.toml}"

# デフォルト設定値
declare -A CONFIG_DEFAULTS=(
    ["general.mode"]="swarm"
    ["general.poll_interval"]="60"
    ["general.timeout"]="21600"
    ["pueue.parallel"]="1"
    ["pueue.group"]="flowgate"
    ["logs.retention_days"]="30"
)

# =============================================================================
# config_get <section> <key> [default]
# 設定値を取得する
#
# Arguments:
#   section - セクション名 (例: general, pueue, logs)
#   key     - キー名 (例: mode, parallel)
#   default - (optional) 値が存在しない場合のデフォルト値
#
# Returns:
#   設定値を標準出力に出力
#   存在しない場合はデフォルト値、またはCONFIG_DEFAULTSの値
# =============================================================================
config_get() {
    local section="${1:-}"
    local key="${2:-}"
    local default="${3:-}"

    if [[ -z "$section" || -z "$key" ]]; then
        echo "Error: config_get requires section and key" >&2
        return 1
    fi

    # デフォルト値の解決
    local default_key="${section}.${key}"
    if [[ -z "$default" && -n "${CONFIG_DEFAULTS[$default_key]:-}" ]]; then
        default="${CONFIG_DEFAULTS[$default_key]}"
    fi

    # 設定ファイルが存在しない場合
    if [[ ! -f "$FLOWGATE_CONFIG_FILE" ]]; then
        echo "$default"
        return 0
    fi

    # セクションとキーから値を取得
    local value
    value=$(_toml_get_value "$section" "$key")

    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# =============================================================================
# config_set <section> <key> <value>
# 設定値を更新する
#
# Arguments:
#   section - セクション名
#   key     - キー名
#   value   - 設定する値
#
# Returns:
#   0: 成功, 1: 失敗
# =============================================================================
config_set() {
    local section="${1:-}"
    local key="${2:-}"
    local value="${3:-}"

    if [[ -z "$section" || -z "$key" ]]; then
        echo "Error: config_set requires section, key, and value" >&2
        return 1
    fi

    # ディレクトリが存在しない場合は作成
    if [[ ! -d "$FLOWGATE_CONFIG_DIR" ]]; then
        mkdir -p "$FLOWGATE_CONFIG_DIR"
    fi

    # 設定ファイルが存在しない場合は初期化
    if [[ ! -f "$FLOWGATE_CONFIG_FILE" ]]; then
        config_init
    fi

    _toml_set_value "$section" "$key" "$value"
}

# =============================================================================
# config_init
# デフォルト設定ファイルを作成する
#
# Returns:
#   0: 成功, 1: 失敗
# =============================================================================
config_init() {
    # ディレクトリが存在しない場合は作成
    if [[ ! -d "$FLOWGATE_CONFIG_DIR" ]]; then
        mkdir -p "$FLOWGATE_CONFIG_DIR"
    fi

    # 既存ファイルがあればバックアップ
    if [[ -f "$FLOWGATE_CONFIG_FILE" ]]; then
        cp "$FLOWGATE_CONFIG_FILE" "${FLOWGATE_CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    fi

    # デフォルト設定を書き込み
    cat > "$FLOWGATE_CONFIG_FILE" << 'EOF'
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

    echo "Created default config: $FLOWGATE_CONFIG_FILE"
}

# =============================================================================
# config_validate
# 設定ファイルを検証する
#
# Returns:
#   0: 有効, 1: 無効（エラー内容を標準エラー出力）
# =============================================================================
config_validate() {
    local errors=()

    # ファイル存在チェック
    if [[ ! -f "$FLOWGATE_CONFIG_FILE" ]]; then
        echo "Error: Config file not found: $FLOWGATE_CONFIG_FILE" >&2
        return 1
    fi

    # [general] セクション検証
    local mode
    mode=$(config_get "general" "mode")
    if [[ "$mode" != "swarm" && "$mode" != "hive" ]]; then
        errors+=("general.mode must be 'swarm' or 'hive' (got: '$mode')")
    fi

    local poll_interval
    poll_interval=$(config_get "general" "poll_interval")
    if ! _is_positive_integer "$poll_interval"; then
        errors+=("general.poll_interval must be a positive integer (got: '$poll_interval')")
    fi

    local timeout
    timeout=$(config_get "general" "timeout")
    if ! _is_positive_integer "$timeout"; then
        errors+=("general.timeout must be a positive integer (got: '$timeout')")
    fi

    # [pueue] セクション検証
    local parallel
    parallel=$(config_get "pueue" "parallel")
    if ! _is_positive_integer "$parallel"; then
        errors+=("pueue.parallel must be a positive integer (got: '$parallel')")
    fi

    local group
    group=$(config_get "pueue" "group")
    if [[ -z "$group" ]]; then
        errors+=("pueue.group must not be empty")
    fi

    # [logs] セクション検証
    local retention_days
    retention_days=$(config_get "logs" "retention_days")
    if ! _is_positive_integer "$retention_days"; then
        errors+=("logs.retention_days must be a positive integer (got: '$retention_days')")
    fi

    # エラーがあれば報告
    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "Config validation failed:" >&2
        for err in "${errors[@]}"; do
            echo "  - $err" >&2
        done
        return 1
    fi

    echo "Config validation passed: $FLOWGATE_CONFIG_FILE"
    return 0
}

# =============================================================================
# config_list [section]
# 設定値を一覧表示する
#
# Arguments:
#   section - (optional) 特定セクションのみ表示
# =============================================================================
config_list() {
    local section="${1:-}"

    if [[ ! -f "$FLOWGATE_CONFIG_FILE" ]]; then
        echo "Config file not found: $FLOWGATE_CONFIG_FILE" >&2
        return 1
    fi

    if [[ -n "$section" ]]; then
        echo "[$section]"
        _toml_list_section "$section"
    else
        # 全セクションを表示
        for sec in general pueue logs; do
            echo "[$sec]"
            _toml_list_section "$sec"
            echo
        done
    fi
}

# =============================================================================
# 内部関数
# =============================================================================

# TOMLからセクション内の値を取得
_toml_get_value() {
    local section="$1"
    local key="$2"
    local in_section=0
    local value=""

    while IFS= read -r line; do
        # 空行・コメント行をスキップ
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # セクションヘッダをチェック
        if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\] ]]; then
            if [[ "${BASH_REMATCH[1]}" == "$section" ]]; then
                in_section=1
            else
                in_section=0
            fi
            continue
        fi

        # セクション内のキーを探す
        if [[ $in_section -eq 1 ]]; then
            # key = value 形式をパース（コメント除去）
            if [[ "$line" =~ ^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.+) ]]; then
                value="${BASH_REMATCH[1]}"
                # 行末コメントを除去
                value=$(echo "$value" | sed 's/[[:space:]]*#.*$//')
                # クォートを除去
                value=$(echo "$value" | sed 's/^["'"'"']\(.*\)["'"'"']$/\1/')
                # 前後の空白を除去
                value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                echo "$value"
                return 0
            fi
        fi
    done < "$FLOWGATE_CONFIG_FILE"

    return 0
}

# TOMLに値を設定
_toml_set_value() {
    local section="$1"
    local key="$2"
    local value="$3"
    local temp_file
    temp_file=$(mktemp)

    local in_section=0
    local key_found=0
    local section_found=0
    local need_quotes=0

    # 数値以外はクォートする
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        need_quotes=1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        # セクションヘッダをチェック
        if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\] ]]; then
            # 前のセクションにキーがなければ追加
            if [[ $in_section -eq 1 && $key_found -eq 0 ]]; then
                if [[ $need_quotes -eq 1 ]]; then
                    echo "$key = \"$value\"" >> "$temp_file"
                else
                    echo "$key = $value" >> "$temp_file"
                fi
                key_found=1
            fi

            if [[ "${BASH_REMATCH[1]}" == "$section" ]]; then
                in_section=1
                section_found=1
            else
                in_section=0
            fi
            echo "$line" >> "$temp_file"
            continue
        fi

        # セクション内のキーを探す
        if [[ $in_section -eq 1 && $key_found -eq 0 ]]; then
            if [[ "$line" =~ ^[[:space:]]*${key}[[:space:]]*= ]]; then
                # キーを更新
                if [[ $need_quotes -eq 1 ]]; then
                    echo "$key = \"$value\"" >> "$temp_file"
                else
                    echo "$key = $value" >> "$temp_file"
                fi
                key_found=1
                continue
            fi
        fi

        echo "$line" >> "$temp_file"
    done < "$FLOWGATE_CONFIG_FILE"

    # ファイル末尾でセクション内の場合、キーを追加
    if [[ $in_section -eq 1 && $key_found -eq 0 ]]; then
        if [[ $need_quotes -eq 1 ]]; then
            echo "$key = \"$value\"" >> "$temp_file"
        else
            echo "$key = $value" >> "$temp_file"
        fi
        key_found=1
    fi

    # セクションが見つからなかった場合、新規作成
    if [[ $section_found -eq 0 ]]; then
        echo "" >> "$temp_file"
        echo "[$section]" >> "$temp_file"
        if [[ $need_quotes -eq 1 ]]; then
            echo "$key = \"$value\"" >> "$temp_file"
        else
            echo "$key = $value" >> "$temp_file"
        fi
    fi

    mv "$temp_file" "$FLOWGATE_CONFIG_FILE"
}

# セクション内の全キー・値を表示
_toml_list_section() {
    local section="$1"
    local in_section=0

    while IFS= read -r line; do
        # 空行をスキップ
        [[ -z "$line" ]] && continue

        # セクションヘッダをチェック
        if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\] ]]; then
            if [[ "${BASH_REMATCH[1]}" == "$section" ]]; then
                in_section=1
            else
                in_section=0
            fi
            continue
        fi

        # セクション内のキー・値を表示
        if [[ $in_section -eq 1 ]]; then
            # コメント行をスキップ
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            # キー = 値 形式のみ表示
            if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_-]+)[[:space:]]*= ]]; then
                echo "  $line"
            fi
        fi
    done < "$FLOWGATE_CONFIG_FILE"
}

# 正の整数かチェック
_is_positive_integer() {
    local value="$1"
    [[ "$value" =~ ^[1-9][0-9]*$ || "$value" == "0" ]] && [[ "$value" -gt 0 ]]
}

# =============================================================================
# メイン（直接実行時のテスト・デバッグ用）
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        init)
            config_init
            ;;
        get)
            config_get "${2:-}" "${3:-}" "${4:-}"
            ;;
        set)
            config_set "${2:-}" "${3:-}" "${4:-}"
            ;;
        validate)
            config_validate
            ;;
        list)
            config_list "${2:-}"
            ;;
        *)
            echo "Usage: $0 {init|get|set|validate|list}"
            echo ""
            echo "Commands:"
            echo "  init                      Create default config"
            echo "  get <section> <key>       Get config value"
            echo "  set <section> <key> <val> Set config value"
            echo "  validate                  Validate config"
            echo "  list [section]            List config values"
            ;;
    esac
fi
