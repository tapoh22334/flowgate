# flowgate

> Bridge GitHub Issues to claude-flow task execution via pueue

## 概要

GitHub Issueにラベルを付けると、claude-flow (swarm/hive-mind) でタスクを実行しPRを作成する。複数リポジトリ対応。

## 使い方

### 自動実行（メイン）

1. GitHub Issueを作成（本文にPRD/タスク内容）
2. ラベルを付ける
3. 待つ（最大1分でキューイング）
4. claude-flowが実装してPR作成

| ラベル | モード |
|--------|--------|
| `flowgate` | デフォルト（FLOWGATE_MODE） |
| `flowgate:swarm` | swarm |
| `flowgate:hive` | hive-mind |

### 手動実行

```bash
flowgate owner/repo 123
flowgate owner/repo -m hive 123
flowgate status
```

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────┐
│ flowgate-watcher (systemd)                              │
│                                                         │
│  監視リポジトリ: ~/.flowgate/repos.meta                │
│    - owner/repo-a                                       │
│    - owner/repo-b                                       │
│                                                         │
│  毎分ポーリング                                         │
│    ├─▶ gh issue list --repo owner/repo-a --label ...   │
│    └─▶ gh issue list --repo owner/repo-b --label ...   │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│ flowgate (CLI)                                          │
│                                                         │
│  flowgate owner/repo 123                                │
│    │                                                    │
│    ├─▶ gh issue view 123 --repo owner/repo             │
│    │                                                    │
│    └─▶ pueue add "..."                                 │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│ pueue (queue)                                           │
│                                                         │
│  Task: owner/repo#123                                   │
│    │                                                    │
│    ├─▶ cd ~/.flowgate/repos/owner/repo                 │
│    ├─▶ git worktree add -b issue-123                   │
│    └─▶ claude-flow swarm/hive-mind "<task>"            │
│          │                                              │
│          └─▶ gh pr create                              │
└─────────────────────────────────────────────────────────┘
```

## ファイル構成

```
flowgate/                         # インストール先
├── check-deps.sh
├── init.sh
├── scripts/
│   ├── flowgate.sh               # CLI
│   └── flowgate-watcher.sh       # 1回実行（timerから呼ばれる）
├── systemd/
│   ├── flowgate.service          # watcher実行用
│   └── flowgate.timer            # 1分間隔トリガー
└── README.md

~/.flowgate/                      # ランタイムデータ
├── config.toml                   # 設定
├── repos.meta                    # 監視リポジトリ一覧
├── logs/
│   ├── watcher.log
│   └── tasks/
│       ├── owner-repo-123.log
│       └── ...
└── repos/                        # 作業ディレクトリ
    ├── owner/
    │   ├── repo-a/
    │   └── repo-b/
    └── ...
```

## 設定

### ~/.flowgate/config.toml

```toml
[general]
mode = "swarm"          # デフォルトモード: swarm | hive
poll_interval = 60      # ポーリング間隔(秒)

[pueue]
parallel = 1            # 並行実行数
group = "flowgate"      # pueueグループ名
```

### ~/.flowgate/repos.meta

```
owner/repo-a
owner/repo-b
another/project
```

## コマンド

### flowgate

```bash
# Issueをキューに追加
flowgate <owner/repo> <issue-number>
flowgate <owner/repo> -m hive <issue-number>

# キュー状態
flowgate status

# リポジトリ管理
flowgate repo add owner/repo      # 監視対象に追加 + clone
flowgate repo remove owner/repo   # 監視対象から削除
flowgate repo list                # 一覧表示
```

## セットアップ

```bash
git clone https://github.com/takoh/flowgate && cd flowgate
./install.sh  # ワンコマンドで完全セットアップ
```

### install.sh

統合インストーラーが以下を自動実行:
1. 依存関係のチェック (git, Node.js 20+, gh CLI, pueue, claude-flow, claude-code)
2. GitHub/Claude認証
3. pueuedの起動とグループ作成
4. ディレクトリ構造の作成
5. スクリプトのインストール (~/.local/bin/)
6. systemdサービスのインストールと有効化

```
$ ./install.sh

flowgate installer
==================

1. 依存関係のチェック
---------------------
  [✓] git 2.x
  [✓] Node.js v20.x
  [✓] gh CLI 2.x
  [✓] pueue 3.x
  [✓] claude-flow
  [✓] claude-code

2. 認証
-------
→ GitHub authentication...
  [✓] Already authenticated

→ Claude authentication...
  [✓] Claude authenticated

3. pueue セットアップ
---------------------
→ Starting pueued...
  [✓] pueued started

→ Creating pueue group 'flowgate'...
  [✓] Group 'flowgate' created

4. ディレクトリ構造の作成
-------------------------
  [✓] Created ~/.flowgate

5. スクリプトのインストール
---------------------------
  [✓] Installed flowgate
  [✓] Installed flowgate-watcher

6. systemd サービスのインストール
---------------------------------
  [✓] flowgate.timer enabled and started

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Installation complete!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Next steps:
  flowgate repo add owner/repo
```

## リポジトリ追加

```
$ flowgate repo add takoh/my-project

Adding repository: takoh/my-project
[✓] Cloned to ~/.flowgate/repos/takoh/my-project
[✓] Added to watch list

Ready! Add 'flowgate' label to any issue in takoh/my-project.
```

## 起動

インストール時に自動的に有効化されます。手動で操作する場合:

```bash
# 状態確認
systemctl --user status flowgate.timer
systemctl --user list-timers

# 手動で有効化（必要な場合のみ）
systemctl --user enable --now flowgate.timer

# 停止
systemctl --user stop flowgate.timer

# ログ確認
journalctl --user -u flowgate -f
tail -f ~/.flowgate/logs/watcher.log

# 手動実行（デバッグ用）
flowgate-watcher
```

## 動作フロー詳細

### flowgate-watcher.sh

```bash
#!/bin/bash
# 1回実行（systemd timerから呼ばれる）

for repo in $(cat ~/.flowgate/repos.meta); do
  for label in "flowgate" "flowgate:swarm" "flowgate:hive"; do
    issues=$(gh issue list --repo "$repo" --label "$label" --json number -q '.[].number')
    
    for issue in $issues; do
      mode=$(parse_mode "$label")
      flowgate "$repo" -m "$mode" "$issue"
      gh issue edit "$issue" --repo "$repo" --remove-label "$label"
    done
  done
done
```

### systemd/flowgate.service

```ini
[Unit]
Description=flowgate watcher

[Service]
Type=oneshot
ExecStart=/path/to/flowgate/scripts/flowgate-watcher.sh
```

### systemd/flowgate.timer

```ini
[Unit]
Description=flowgate watcher timer

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
```

### flowgate.sh (キューイング)

```bash
flowgate owner/repo 123
  │
  ├─▶ BODY=$(gh issue view 123 --repo owner/repo --json body -q .body)
  │
  ├─▶ TASK="$BODY\n---\n完了後、gh CLIを使ってPRを作成してください。"
  │
  ├─▶ REPO_DIR=~/.flowgate/repos/owner/repo
  │
  └─▶ pueue add --group flowgate -- bash -c "
        cd $REPO_DIR
        BRANCH=issue-123
        git worktree add -b $BRANCH .worktrees/$BRANCH
        cd .worktrees/$BRANCH
        npx claude-flow@alpha swarm '$TASK' --claude
      "
```

## 依存

- Node.js 20+
- git
- gh CLI
- pueue / pueued
- claude-flow (npm)
- claude code (npm)

## 制約・注意

- 初回は手動で認証が必要
- Claude認証トークンの有効期限切れ時は `./init.sh --reauth`
- pueuedが起動している必要あり

## オブザーバビリティ

### ログ出力

```
~/.flowgate/logs/
├── watcher.log                    # watcher全体
└── tasks/
    ├── owner-repo-123.log         # タスクごと
    ├── owner-repo-124.log
    └── another-project-45.log
```

- ログローテーション: 30日保持、古いものは自動削除

### Issueコメント

**開始時:**
```
🚀 flowgate: タスク開始 (swarm)
ログ: ~/.flowgate/logs/tasks/owner-repo-123.log
```

**成功時:**
```
✅ flowgate: 完了
PR: #456
```

**失敗時:**
```
❌ flowgate: 失敗

エラー内容（末尾100行程度）

フルログ: ~/.flowgate/logs/tasks/owner-repo-123.log
```

**タイムアウト時:**
```
⏱️ flowgate: タイムアウト (6時間超過)
フルログ: ~/.flowgate/logs/tasks/owner-repo-123.log
```

### ラベル遷移

```
[トリガー]              [実行中]              [結果]
flowgate        ─┐
flowgate:swarm  ─┼─▶ flowgate:processing ─┬─▶ (ラベル削除) 成功
flowgate:hive   ─┘                        ├─▶ flowgate:failed
                                          └─▶ flowgate:timeout
```

### リトライ

`flowgate:failed` または `flowgate:timeout` を手動で `flowgate` に付け替えると再実行される。

## 設定

### ~/.flowgate/config.toml (フル版)

```toml
[general]
mode = "swarm"          # デフォルトモード: swarm | hive
poll_interval = 60      # ポーリング間隔(秒)
timeout = 21600         # タイムアウト(秒) = 6時間

[pueue]
parallel = 1            # 並行実行数
group = "flowgate"      # pueueグループ名

[logs]
retention_days = 30     # ログ保持日数
```