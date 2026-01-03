# flowgate Architecture Document

## 1. システム概要

flowgateは、GitHub IssueをトリガーとしてAI駆動の開発タスクを自動実行するブリッジシステムです。

### 設計原則

1. **シンプルさ**: Bashスクリプトベースで依存を最小化
2. **信頼性**: pueueによる堅牢なタスクキュー管理
3. **可観測性**: ログ、ラベル、Issueコメントによる状態可視化
4. **拡張性**: 複数リポジトリ対応、モード切替可能

---

## 2. コンポーネント構成

```
┌─────────────────────────────────────────────────────────────────────┐
│                         flowgate システム                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────┐  │
│  │ systemd      │    │ flowgate-    │    │ flowgate.sh          │  │
│  │ timer        │───▶│ watcher.sh   │───▶│ (CLI)                │  │
│  │ (1分間隔)    │    │              │    │                      │  │
│  └──────────────┘    └──────────────┘    └──────────┬───────────┘  │
│                                                      │              │
│                                                      ▼              │
│                                          ┌──────────────────────┐  │
│                                          │ pueue                │  │
│                                          │ (タスクキュー)        │  │
│                                          └──────────┬───────────┘  │
│                                                      │              │
│                                                      ▼              │
│                                          ┌──────────────────────┐  │
│                                          │ claude-flow          │  │
│                                          │ (swarm/hive-mind)    │  │
│                                          └──────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.1 コンポーネント一覧

| コンポーネント | ファイル | 責務 |
|--------------|---------|------|
| CLI | `scripts/flowgate.sh` | ユーザーインターフェース、タスク登録 |
| Watcher | `scripts/flowgate-watcher.sh` | Issueポーリング、自動キューイング |
| Installer | `install.sh` | 依存関係のインストール |
| Initializer | `init.sh` | 認証・初期設定 |
| Timer | `systemd/flowgate.timer` | 定期実行トリガー |
| Service | `systemd/flowgate.service` | watcher実行定義 |

---

## 3. ディレクトリ構造

### 3.1 インストールディレクトリ

```
flowgate/                         # $FLOWGATE_HOME
├── install.sh                    # 依存インストールスクリプト
├── init.sh                       # 初期設定スクリプト
├── scripts/
│   ├── flowgate.sh               # メインCLI
│   ├── flowgate-watcher.sh       # 監視スクリプト
│   └── lib/
│       ├── common.sh             # 共通関数
│       ├── config.sh             # 設定読み込み
│       ├── github.sh             # GitHub操作
│       ├── pueue.sh              # pueue操作
│       └── log.sh                # ログ関数
├── systemd/
│   ├── flowgate.service
│   └── flowgate.timer
└── README.md
```

### 3.2 ランタイムディレクトリ

```
~/.flowgate/                      # $FLOWGATE_DATA
├── config.toml                   # 設定ファイル
├── repos.meta                    # 監視リポジトリ一覧
├── processed.meta                # 処理済みIssue記録（重複防止）
├── logs/
│   ├── watcher.log               # Watcherログ
│   └── tasks/
│       └── {owner}-{repo}-{issue}.log
└── repos/                        # 作業ディレクトリ
    └── {owner}/
        └── {repo}/
            ├── .git/
            └── .worktrees/
                └── issue-{number}/
```

---

## 4. データフロー

### 4.1 自動実行フロー

```
[GitHub Issue]
      │
      │ ラベル付与: flowgate / flowgate:swarm / flowgate:hive
      ▼
┌─────────────────────────────────────────────────────────────────┐
│ flowgate-watcher.sh                                             │
│                                                                 │
│  1. repos.meta から監視リポジトリ一覧を読み込み                   │
│  2. 各リポジトリのflowgateラベル付きIssueを取得                   │
│  3. 未処理のIssueに対して flowgate CLI を呼び出し                 │
│  4. ラベルを flowgate:processing に変更                          │
└─────────────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────────────┐
│ flowgate.sh (CLI)                                               │
│                                                                 │
│  1. Issue本文を取得 (gh issue view)                              │
│  2. タスク説明を生成（本文 + PR作成指示）                          │
│  3. Issueに開始コメント投稿                                       │
│  4. pueueにタスク追加                                            │
└─────────────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────────────┐
│ pueue (タスク実行)                                               │
│                                                                 │
│  1. git worktreeで作業ブランチ作成                               │
│  2. claude-flow 実行 (swarm/hive-mind)                          │
│  3. 完了後: PR作成 (gh pr create)                                │
│  4. 結果をIssueにコメント                                        │
│  5. ラベル更新（削除 or flowgate:failed/timeout）                │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 手動実行フロー

```
[ユーザー]
      │
      │ flowgate owner/repo 123
      ▼
┌─────────────────────────────────────────────────────────────────┐
│ flowgate.sh (CLI)                                               │
│                                                                 │
│  （自動実行フローと同じ処理）                                     │
└─────────────────────────────────────────────────────────────────┘
```

### 4.3 状態遷移図

```
                    ┌─────────────────┐
                    │   Issue作成     │
                    └────────┬────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      ラベル付与                                  │
│  flowgate | flowgate:swarm | flowgate:hive                      │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │ flowgate:       │
                    │ processing      │
                    └────────┬────────┘
                             │
           ┌─────────────────┼─────────────────┐
           ▼                 ▼                 ▼
    ┌────────────┐   ┌────────────┐   ┌────────────┐
    │ 成功       │   │ 失敗       │   │ タイムアウト│
    │ (ラベル削除)│   │ flowgate:  │   │ flowgate:  │
    │ + PR作成   │   │ failed     │   │ timeout    │
    └────────────┘   └─────┬──────┘   └─────┬──────┘
                           │                │
                           └───────┬────────┘
                                   │ 手動でラベル変更
                                   ▼
                          ┌─────────────────┐
                          │ リトライ         │
                          │ (flowgateに戻す)│
                          └─────────────────┘
```

---

## 5. インターフェース定義

### 5.1 スクリプト間インターフェース

#### flowgate.sh (CLI)

```bash
# 基本使用法
flowgate <owner/repo> [options] <issue-number>
flowgate status
flowgate repo <subcommand> [args]

# オプション
#   -m, --mode <mode>   実行モード (swarm|hive)
#   -v, --verbose       詳細出力
#   -h, --help          ヘルプ表示

# 終了コード
#   0: 成功（キューイング完了）
#   1: 一般エラー
#   2: 引数エラー
#   3: 設定エラー
#   4: GitHub API エラー
#   5: pueue エラー
```

#### flowgate-watcher.sh

```bash
# 基本使用法
flowgate-watcher.sh

# 環境変数
#   FLOWGATE_DATA    ランタイムディレクトリ (default: ~/.flowgate)
#   FLOWGATE_HOME    インストールディレクトリ

# 終了コード
#   0: 成功
#   1: エラー
```

### 5.2 ライブラリ関数インターフェース

#### lib/common.sh

```bash
# ログ出力
log_info <message>
log_warn <message>
log_error <message>
log_debug <message>

# ユーティリティ
die <message> [exit_code]       # エラー終了
require_command <command>        # コマンド存在確認
ensure_dir <path>               # ディレクトリ作成
```

#### lib/config.sh

```bash
# 設定読み込み
config_load                      # config.tomlを読み込み
config_get <section> <key>       # 値取得
config_get_or_default <section> <key> <default>

# 定数
FLOWGATE_DATA="${FLOWGATE_DATA:-$HOME/.flowgate}"
CONFIG_FILE="$FLOWGATE_DATA/config.toml"
```

#### lib/github.sh

```bash
# Issue操作
gh_issue_get_body <repo> <issue>              # Issue本文取得
gh_issue_add_comment <repo> <issue> <body>    # コメント追加
gh_issue_add_label <repo> <issue> <label>     # ラベル追加
gh_issue_remove_label <repo> <issue> <label>  # ラベル削除

# リポジトリ操作
gh_repo_clone <repo> <dest>                   # クローン
```

#### lib/pueue.sh

```bash
# タスク操作
pueue_add_task <group> <command> <label>      # タスク追加
pueue_get_status <group>                      # グループ状態取得
pueue_ensure_group <group>                    # グループ作成確認

# 定数
PUEUE_GROUP="flowgate"
```

#### lib/log.sh

```bash
# タスクログ
task_log_path <owner> <repo> <issue>          # ログパス生成
task_log_write <path> <message>               # ログ書き込み
task_log_cleanup <days>                       # 古いログ削除
```

---

## 6. 設定ファイルスキーマ

### 6.1 config.toml

```toml
# ~/.flowgate/config.toml

[general]
# デフォルト実行モード: "swarm" | "hive"
mode = "swarm"

# ポーリング間隔（秒）- systemd timerで制御するため参考値
poll_interval = 60

# タスクタイムアウト（秒）
timeout = 21600  # 6時間

[pueue]
# 並行実行数
parallel = 1

# pueueグループ名
group = "flowgate"

[logs]
# ログ保持日数
retention_days = 30

# ログレベル: "debug" | "info" | "warn" | "error"
level = "info"

[github]
# Issueコメントの有効/無効
comments_enabled = true
```

### 6.2 repos.meta

```
# ~/.flowgate/repos.meta
# 1行1リポジトリ、owner/repo 形式
# コメント行は # で開始

owner/repo-a
owner/repo-b
another-owner/project
```

### 6.3 processed.meta

```
# ~/.flowgate/processed.meta
# 処理済みIssueの記録（重複防止用）
# 形式: owner/repo#issue:timestamp

owner/repo-a#123:1704326400
owner/repo-b#45:1704326460
```

---

## 7. 共通関数一覧

### 7.1 カテゴリ別関数リスト

| カテゴリ | 関数名 | 説明 |
|---------|--------|------|
| **ログ** | `log_info` | 情報ログ出力 |
| | `log_warn` | 警告ログ出力 |
| | `log_error` | エラーログ出力 |
| | `log_debug` | デバッグログ出力 |
| **設定** | `config_load` | TOML設定読み込み |
| | `config_get` | 設定値取得 |
| **GitHub** | `gh_issue_get_body` | Issue本文取得 |
| | `gh_issue_add_comment` | コメント追加 |
| | `gh_issue_add_label` | ラベル追加 |
| | `gh_issue_remove_label` | ラベル削除 |
| | `gh_repo_clone` | リポジトリクローン |
| **pueue** | `pueue_add_task` | タスク追加 |
| | `pueue_get_status` | 状態取得 |
| | `pueue_ensure_group` | グループ確保 |
| **ユーティリティ** | `die` | エラー終了 |
| | `require_command` | コマンド確認 |
| | `ensure_dir` | ディレクトリ確保 |
| | `parse_repo` | owner/repo パース |
| | `sanitize_filename` | ファイル名サニタイズ |
| **タスク** | `task_log_path` | ログパス生成 |
| | `task_log_write` | ログ書き込み |
| | `task_log_cleanup` | ログクリーンアップ |
| | `is_processed` | 処理済み確認 |
| | `mark_processed` | 処理済みマーク |

---

## 8. エラーハンドリング方針

### 8.1 エラーカテゴリと対応

| カテゴリ | 例 | 対応 |
|---------|-----|------|
| **設定エラー** | config.toml不正、repos.meta不在 | 早期終了、ログ出力 |
| **認証エラー** | gh/Claude未認証 | ユーザーに再認証を促す |
| **ネットワークエラー** | GitHub API失敗 | リトライ後、ラベル付与して報告 |
| **タスクエラー** | claude-flow失敗 | ログ保存、Issue通知、ラベル変更 |
| **タイムアウト** | 実行時間超過 | 強制終了、Issue通知、ラベル変更 |

### 8.2 エラー処理の原則

1. **Fail Fast**: 致命的エラーは早期に検出・終了
2. **Graceful Degradation**: 非致命的エラーはログして継続
3. **User Notification**: 重要なエラーはIssueコメントで通知
4. **Recoverability**: ラベルによるリトライ機構

### 8.3 エラーコード体系

```bash
# 終了コード定義
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_INVALID_ARGS=2
readonly EXIT_CONFIG_ERROR=3
readonly EXIT_GITHUB_ERROR=4
readonly EXIT_PUEUE_ERROR=5
readonly EXIT_TIMEOUT=6
readonly EXIT_CLAUDE_ERROR=7
```

### 8.4 エラーログフォーマット

```
[2024-01-04 12:34:56] [ERROR] [flowgate.sh:123] メッセージ
│                      │       │               │
│                      │       │               └─ エラー内容
│                      │       └─ ファイル:行番号
│                      └─ ログレベル
└─ タイムスタンプ
```

---

## 9. 依存関係図

```
┌─────────────────────────────────────────────────────────────────┐
│                        外部依存                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌───────────┐ │
│  │ Node.js    │  │ git        │  │ gh CLI     │  │ pueue     │ │
│  │ 20+        │  │            │  │            │  │ pueued    │ │
│  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘  └─────┬─────┘ │
│        │               │               │               │       │
│        │               │               │               │       │
│        └───────────────┴───────┬───────┴───────────────┘       │
│                                │                               │
└────────────────────────────────┼───────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                     flowgate スクリプト群                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌────────────┐                      ┌────────────────────────┐ │
│  │ install.sh │                      │ systemd/               │ │
│  │ init.sh    │                      │  ├─ flowgate.service   │ │
│  └─────┬──────┘                      │  └─ flowgate.timer     │ │
│        │                             └───────────┬────────────┘ │
│        │ セットアップ時                           │              │
│        ▼                                         ▼              │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                     scripts/lib/                            ││
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐       ││
│  │  │common.sh │ │config.sh │ │github.sh │ │pueue.sh  │       ││
│  │  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘       ││
│  │       │            │            │            │              ││
│  │       └────────────┴─────┬──────┴────────────┘              ││
│  │                          │                                  ││
│  └──────────────────────────┼──────────────────────────────────┘│
│                             │ source                            │
│                             ▼                                   │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                     scripts/                                ││
│  │  ┌────────────────────┐  ┌────────────────────────┐        ││
│  │  │ flowgate.sh        │  │ flowgate-watcher.sh    │        ││
│  │  │ (CLI)              │  │ (監視)                  │        ││
│  │  └─────────┬──────────┘  └───────────┬────────────┘        ││
│  │            │                         │                      ││
│  └────────────┼─────────────────────────┼──────────────────────┘│
│               │                         │                       │
└───────────────┼─────────────────────────┼───────────────────────┘
                │                         │
                ▼                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                     NPM パッケージ                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌────────────────────┐  ┌────────────────────┐                │
│  │ claude-flow        │  │ claude code        │                │
│  │ (npx claude-flow)  │  │ (npx claude)       │                │
│  └────────────────────┘  └────────────────────┘                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 10. セキュリティ考慮事項

### 10.1 認証情報

- GitHub認証: `gh auth` でトークン管理（~/.config/gh/）
- Claude認証: Claude Code のOAuth管理
- 認証情報はflowgate内に保存しない

### 10.2 入力検証

- Issue番号: 数値のみ許可
- リポジトリ名: `owner/repo` パターン検証
- ファイルパス: パストラバーサル防止

### 10.3 実行環境

- pueueグループで分離
- worktreeで作業ディレクトリを分離
- タイムアウトで無限実行を防止

---

## 11. 拡張ポイント

### 11.1 将来の拡張候補

1. **Webhook対応**: ポーリングからWebhookへの移行
2. **Web UI**: 状態確認用ダッシュボード
3. **通知連携**: Slack/Discord通知
4. **メトリクス**: 実行統計の収集・可視化

### 11.2 プラグイン機構（将来構想）

```
~/.flowgate/plugins/
├── pre-task/      # タスク開始前フック
├── post-task/     # タスク完了後フック
└── formatters/    # 出力フォーマッター
```

---

## 付録A: 環境変数一覧

| 変数名 | デフォルト | 説明 |
|--------|-----------|------|
| `FLOWGATE_HOME` | (インストール先) | インストールディレクトリ |
| `FLOWGATE_DATA` | `~/.flowgate` | ランタイムデータディレクトリ |
| `FLOWGATE_MODE` | `swarm` | デフォルト実行モード |
| `FLOWGATE_LOG_LEVEL` | `info` | ログレベル |
| `FLOWGATE_TIMEOUT` | `21600` | タイムアウト（秒） |

---

## 付録B: ファイル命名規則

| パターン | 例 | 用途 |
|----------|-----|------|
| `{owner}-{repo}-{issue}.log` | `takoh-myproject-123.log` | タスクログ |
| `issue-{number}` | `issue-123` | worktreeブランチ名 |
| `{owner}/{repo}` | `takoh/myproject` | repos.meta内の形式 |
