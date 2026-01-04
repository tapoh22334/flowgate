# flowgate

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Node.js](https://img.shields.io/badge/Node.js-20%2B-green.svg)](https://nodejs.org/)
[![GitHub CLI](https://img.shields.io/badge/GitHub%20CLI-required-blue.svg)](https://cli.github.com/)

> GitHub Issue から claude-flow タスク実行を自動化し、PRを作成するブリッジツール

## 概要

flowgateは、GitHub Issueにラベルを付けるだけで、[claude-flow](https://github.com/ruvnet/claude-flow)（swarm/hive-mind）を使ってタスクを自動実行し、Pull Requestを作成するツールです。複数リポジトリに対応しています。

## 特徴

- **ラベル駆動**: Issueにラベルを付けるだけで自動実行
- **複数リポジトリ対応**: 1つのインスタンスで複数リポジトリを監視
- **2つの実行モード**: swarm（並列）と hive-mind（協調）を選択可能
- **キュー管理**: pueueによる堅牢なタスクキュー管理
- **自動PR作成**: タスク完了後に自動でPull Requestを作成
- **オブザーバビリティ**: Issueコメントとログによる進捗追跡

## セキュリティ

> **重要**: flowgate は Issue の内容を自動実行するため、セキュリティに十分注意してください。

### OWNER限定実行

flowgate は **リポジトリオーナーが作成した Issue のみ** を処理します。

- Public リポジトリでは誰でも Issue を作成できますが、オーナー以外の Issue は無視されます
- これにより、悪意のあるユーザーによる任意コード実行を防止します
- GitHub の認証システムにより、Issue 作成者の偽装は不可能です

### Public リポジトリの警告

```bash
$ flowgate repo add owner/public-repo
[INFO] Adding repository: owner/public-repo

[WARN] This is a PUBLIC repository!
[WARN] Security: Only issues created by the repository OWNER will be processed.
[WARN] Other users' issues will be ignored for security reasons.

Continue adding this public repository? [y/N]:
```

### 推奨事項

| 環境 | 推奨度 | 備考 |
|------|--------|------|
| Private リポジトリ | ✅ 推奨 | コラボレーターのみ Issue 作成可能 |
| Public リポジトリ | ⚠️ 注意 | OWNER の Issue のみ実行される |

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
│    ├──▶ gh issue list --repo owner/repo-a --label ...   │
│    └──▶ gh issue list --repo owner/repo-b --label ...   │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│ flowgate (CLI)                                          │
│                                                         │
│  flowgate owner/repo 123                                │
│    │                                                    │
│    ├──▶ gh issue view 123 --repo owner/repo             │
│    │                                                    │
│    └──▶ pueue add "..."                                 │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│ pueue (queue)                                           │
│                                                         │
│  Task: owner/repo#123                                   │
│    │                                                    │
│    ├──▶ cd ~/.flowgate/repos/owner/repo                 │
│    ├──▶ git worktree add -b issue-123                   │
│    └──▶ claude-flow swarm/hive-mind "<task>"            │
│          │                                              │
│          └──▶ gh pr create                              │
└─────────────────────────────────────────────────────────┘
```

## クイックスタート

### 必須依存関係

flowgate を使用する前に、以下の依存関係をインストールしてください：

#### 基本ツール
- **git** - バージョン管理
- **Node.js 20+** - JavaScript ランタイム
- **GitHub CLI (gh)** - GitHub操作 ([インストール方法](https://cli.github.com/))
- **pueue / pueued** - タスクキュー管理 ([インストール方法](https://github.com/Nukesor/pueue))

#### Claude関連ツール (npm経由)
```bash
npm install -g @anthropic-ai/claude-flow@alpha
npm install -g @anthropic-ai/claude-code
```

### インストール

ワンコマンドでセットアップ完了：

```bash
git clone https://github.com/takoh/flowgate && cd flowgate
./install.sh
```

インストーラーは以下を自動実行します：

```
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
  [✓] Created ~/.flowgate/logs
  [✓] Created config.toml

5. スクリプトのインストール
---------------------------
  [✓] Installed flowgate
  [✓] Installed flowgate-watcher

6. systemd サービスのインストール
---------------------------------
  [✓] Installed flowgate.service
  [✓] Installed flowgate.timer
  [✓] systemd daemon reloaded

Enable and start flowgate.timer now? [y/N]: y
  [✓] flowgate.timer enabled and started

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Installation complete!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

> **Note**: 依存関係が不足している場合、インストーラーがOS別のインストール方法を表示します

### リポジトリ追加

監視対象のリポジトリを追加します：

```bash
flowgate repo add owner/my-project
```

```
Adding repository: owner/my-project
[✓] Cloned to ~/.flowgate/repos/owner/my-project
[✓] Added to watch list

Ready! Add 'flowgate' label to any issue in owner/my-project.
```

これで完了です！GitHub Issueに`flowgate`ラベルを付けると、1分以内に自動実行されます。

## 使い方

### 自動実行フロー

1. **GitHub Issueを作成** - 本文にPRD/タスク内容を記載
2. **ラベルを付ける** - `flowgate` または実行モード指定ラベル
3. **待つ** - 最大1分でキューイング
4. **完了** - claude-flowが実装してPRを作成

### 手動実行

```bash
# Issueをキューに追加
flowgate owner/repo 123

# モード指定で追加
flowgate owner/repo -m hive 123

# キュー状態確認
flowgate status
```

### リポジトリ管理

```bash
# 監視対象に追加 + clone
flowgate repo add owner/repo

# 監視対象から削除
flowgate repo remove owner/repo

# 一覧表示
flowgate repo list
```

### ラベル説明

#### トリガーラベル

| ラベル | 説明 |
|--------|------|
| `flowgate` | デフォルトモード（config.tomlのmode設定に従う） |
| `flowgate:swarm` | swarmモードで実行 |
| `flowgate:hive` | hive-mindモードで実行 |

#### ステータスラベル

| ラベル | 説明 |
|--------|------|
| `flowgate:processing` | 実行中 |
| `flowgate:failed` | 失敗 |
| `flowgate:timeout` | タイムアウト（6時間超過） |

#### ラベル遷移

```
[トリガー]              [実行中]              [結果]
flowgate        ─┐
flowgate:swarm  ─┼─▶ flowgate:processing ─┬─▶ (ラベル削除) 成功
flowgate:hive   ─┘                        ├─▶ flowgate:failed
                                          └─▶ flowgate:timeout
```

### リトライ

`flowgate:failed` または `flowgate:timeout` を手動で `flowgate` に付け替えると再実行されます。

## 設定

### ~/.flowgate/config.toml

```toml
# flowgate configuration
mode = "swarm"          # デフォルト実行モード: swarm | hive
group = "flowgate"      # pueueグループ名
```

### ポーリング間隔の変更

ポーリング間隔はsystemd timerで管理されています。デフォルトは1分間隔です。

変更するには、timerファイルを直接編集してください：

```bash
# timerファイルを編集
vim ~/.config/systemd/user/flowgate.timer

# OnUnitActiveSecの値を変更（例: 5分間隔にする場合）
# OnUnitActiveSec=1min → OnUnitActiveSec=5min

# 変更を反映
systemctl --user daemon-reload
systemctl --user restart flowgate.timer

# 確認
systemctl --user list-timers
```

### ~/.flowgate/repos.meta

監視対象リポジトリの一覧です：

```
owner/repo-a
owner/repo-b
another/project
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

## オブザーバビリティ

### ログ

```
~/.flowgate/logs/
├── watcher.log                    # watcher全体
└── tasks/
    ├── owner-repo-123.log         # タスクごと
    ├── owner-repo-124.log
    └── another-project-45.log
```


### ログ確認

```bash
# journalでリアルタイム確認
journalctl --user -u flowgate -f

# 手動実行（デバッグ用）
./scripts/flowgate-watcher.sh
```

### Issueコメント

タスクの進捗はIssueに自動コメントされます：

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

## トラブルシューティング

### 認証エラー

**症状**: `gh: authentication required` または `Claude: not authenticated`

**解決方法**:
```bash
./install.sh --reauth
```

### pueuedが起動していない

**症状**: `pueue: connection refused`

**解決方法**:
```bash
pueued -d  # デーモンとして起動
```

### タスクがキューイングされない

**確認事項**:
1. リポジトリが監視対象に追加されているか確認
   ```bash
   flowgate repo list
   ```
2. systemd timerが動作しているか確認
   ```bash
   systemctl --user status flowgate.timer
   systemctl --user list-timers
   ```

   もし停止している場合は有効化:
   ```bash
   systemctl --user enable --now flowgate.timer
   ```

3. ラベルが正しく付いているか確認（`flowgate`, `flowgate:swarm`, `flowgate:hive`）

### ログの確認方法

```bash
# watcher全体のログ
cat ~/.flowgate/logs/watcher.log

# 特定タスクのログ
cat ~/.flowgate/logs/tasks/owner-repo-123.log
```

## アンインストール

flowgateを完全に削除する場合:

```bash
./uninstall.sh
```

アンインストーラーは以下を実行します:

```
flowgate uninstaller
=====================

1. systemd サービスの削除
-------------------------
→ Stopping and disabling flowgate.timer...
  [✓] Stopped flowgate.timer
  [✓] Disabled flowgate.timer

→ Removing systemd unit files...
  [✓] Removed flowgate.timer
  [✓] Removed flowgate.service
  [✓] systemd daemon reloaded

2. スクリプトの削除
-------------------
→ Removing flowgate scripts from ~/.local/bin...
  [✓] Removed flowgate
  [✓] Removed flowgate-watcher

3. pueue グループの削除
-----------------------
→ Checking for flowgate group...
  [✓] Removed pueue group 'flowgate'

4. データディレクトリの削除
---------------------------
[!] This will permanently delete:
  - Configuration: ~/.flowgate/config.toml
  - Repository list: ~/.flowgate/repos.meta
  - Logs: ~/.flowgate/logs/
  - Cloned repositories: ~/.flowgate/repos/

Delete ~/.flowgate? [y/N]: y
  [✓] Removed ~/.flowgate

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Uninstallation complete!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### オプション

```bash
# 確認なしで完全削除
./uninstall.sh -y
```

> **Note**: データディレクトリ (`~/.flowgate`) の削除は確認が入ります。保持したい場合は `N` を選択してください。

## 貢献方法

1. このリポジトリをフォーク
2. 機能ブランチを作成 (`git checkout -b feature/amazing-feature`)
3. 変更をコミット (`git commit -m 'Add amazing feature'`)
4. ブランチにプッシュ (`git push origin feature/amazing-feature`)
5. Pull Requestを作成

## ライセンス

MIT License - 詳細は [LICENSE](LICENSE) ファイルを参照してください。
