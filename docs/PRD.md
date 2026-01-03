# flowgate

> Bridge GitHub Issues to claude-flow task execution via pueue

## 概要

GitHub Issueにラベルを付けると、claude-flow (swarm/hive-mind) でタスクを実行しPRを作成する。全てDockerコンテナ内で完結。

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
docker exec flowgate flowgate 123
docker exec flowgate flowgate -m hive 123
docker exec flowgate flowgate status
```

## アーキテクチャ

```
┌─────────────────────────────────────────────────────┐
│ Docker Container                                    │
│                                                     │
│  ┌─────────────────┐    ┌─────────────────┐        │
│  │ flowgate-watcher│───▶│    flowgate     │        │
│  │ (cron 1min)     │    │     (CLI)       │        │
│  └─────────────────┘    └────────┬────────┘        │
│                                  │                  │
│                                  ▼                  │
│                         ┌─────────────────┐        │
│                         │     pueue       │        │
│                         │    (queue)      │        │
│                         └────────┬────────┘        │
│                                  │                  │
│                                  ▼                  │
│  ┌─────────────────┐    ┌─────────────────┐        │
│  │  claude code    │◀───│  claude-flow    │        │
│  │  (認証済み)     │    │ swarm/hive-mind │        │
│  └─────────────────┘    └─────────────────┘        │
│                                  │                  │
│                                  ▼                  │
│                         ┌─────────────────┐        │
│                         │   git worktree  │        │
│                         │   + gh pr create│        │
│                         └─────────────────┘        │
└─────────────────────────────────────────────────────┘
         │
         │ volumes (永続化)
         ▼
    ~/.claude/        # Claude認証
    ~/.config/gh/     # GitHub認証
    ./repos/          # リポジトリ
```

## 動作フロー

```
1. flowgate-watcher (cron毎分)
   │
   ├─▶ gh issue list --repo $REPO --label "flowgate*"
   │
   ├─▶ ラベルからモード判定
   │     flowgate:swarm → swarm
   │     flowgate:hive  → hive
   │     flowgate       → $FLOWGATE_MODE
   │
   ├─▶ flowgate -m <mode> <issue-number>
   │
   └─▶ gh issue edit --remove-label <label>

2. flowgate (CLI)
   │
   ├─▶ gh issue view <n> --json body
   │
   ├─▶ タスク生成 (本文 + PR作成指示)
   │
   └─▶ pueue add "..."

3. pueue (実行時)
   │
   ├─▶ git worktree add -b issue-<n>
   │
   ├─▶ cd .worktrees/issue-<n>
   │
   └─▶ claude-flow swarm/hive-mind "<task>"
         │
         └─▶ (Claude が実装 + gh pr create)
```

## ファイル構成

```
flowgate/
├── Dockerfile
├── docker-compose.yml
├── entrypoint.sh
├── scripts/
│   ├── flowgate.sh
│   └── flowgate-watcher.sh
├── .env.example
└── README.md
```

## 環境変数

| 変数 | 必須 | 説明 | 例 |
|------|------|------|-----|
| GITHUB_REPO | ✓ | 監視対象リポジトリ | owner/repo |
| FLOWGATE_MODE | | デフォルトモード | swarm / hive |
| POLL_INTERVAL | | ポーリング間隔(秒) | 60 |
| PUEUE_PARALLEL | | 並行実行数 | 2 |

## セットアップ

```bash
git clone https://github.com/takoh/flowgate && cd flowgate
./init.sh owner/repo
```

### init.sh の動作

```
$ ./init.sh owner/repo

flowgate setup
==============
[✓] Docker running
[✓] Container built
[ ] GitHub authenticated
[ ] Claude authenticated  
[ ] Repository cloned

→ Starting GitHub auth...
  Open: https://github.com/login/device
  Enter code: XXXX-XXXX
  Waiting... [✓]

→ Starting Claude auth...
  Open: https://claude.ai/oauth/...
  Waiting... [✓]

→ Cloning repository...
  [✓] owner/repo cloned

Setup complete!
Add 'flowgate' label to any issue to start.
```

### init.sh 内部フロー

```
1. 事前チェック
   ├─ docker --version
   └─ docker compose version

2. 環境構築
   ├─ .env 生成 (GITHUB_REPO=$1)
   ├─ docker compose build
   └─ docker compose up -d

3. GitHub認証
   └─ docker exec flowgate gh auth login --web
      (Device code flow)

4. Claude認証
   └─ docker exec flowgate claude login
      (OAuth - URL表示して手動でブラウザ)

5. リポジトリclone
   └─ docker exec flowgate git clone https://github.com/$1 /repos/repo

6. 完了メッセージ
```

### 再セットアップ / 認証更新

```bash
# 認証だけやり直し
./init.sh --reauth

# 全部やり直し
./init.sh --reset owner/repo
```

## 依存（コンテナ内）

- Ubuntu 24.04
- Node.js 20+
- git
- gh CLI
- pueue / pueued
- claude-flow (npm)
- claude code (npm)

## Volume

| パス | 用途 |
|------|------|
| `~/.claude` | Claude認証情報 |
| `~/.config/gh` | GitHub認証情報 |
| `./repos` | 作業リポジトリ |
| `pueue-data` | pueueの状態 |

## 制約・注意

- 初回は手動で `claude login` / `gh auth login` が必要
- Claude認証トークンの有効期限切れ時は再認証
- 1コンテナ = 1リポジトリを想定