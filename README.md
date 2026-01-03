# flowgate

> Bridge GitHub Issues to claude-flow task execution via pueue

Automatically execute AI-powered development tasks by labeling GitHub Issues. flowgate monitors your repository, queues tasks via pueue, and creates Pull Requests using claude-flow (swarm/hive-mind mode).

## Quick Start

```bash
# 1. Clone and initialize
git clone https://github.com/takoh/flowgate && cd flowgate
./init.sh owner/repo

# 2. Create a GitHub Issue with your task description

# 3. Add the 'flowgate' label - PR will be created automatically
```

## Usage

### Automatic Execution (Primary)

1. Create a GitHub Issue (body contains PRD/task description)
2. Add a label to trigger execution
3. Wait (queued within 1 minute)
4. claude-flow implements and creates a PR

| Label | Mode |
|-------|------|
| `flowgate` | Default (uses FLOWGATE_MODE) |
| `flowgate:swarm` | swarm mode |
| `flowgate:hive` | hive-mind mode |

### Manual Execution

```bash
# Execute specific issue
docker exec flowgate flowgate 123

# Execute with specific mode
docker exec flowgate flowgate -m hive 123

# Check queue status
docker exec flowgate flowgate status
```

## Architecture

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
│  │  (authenticated)│    │ swarm/hive-mind │        │
│  └─────────────────┘    └─────────────────┘        │
│                                  │                  │
│                                  ▼                  │
│                         ┌─────────────────┐        │
│                         │   git worktree  │        │
│                         │   + gh pr create│        │
│                         └─────────────────┘        │
└─────────────────────────────────────────────────────┘
         │
         │ volumes (persistent)
         ▼
    ~/.claude/        # Claude authentication
    ~/.config/gh/     # GitHub authentication
    ./repos/          # Repository
```

## Environment Variables

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `GITHUB_REPO` | Yes | Target repository (owner/repo format) | - |
| `FLOWGATE_MODE` | No | Default execution mode | `swarm` |
| `POLL_INTERVAL` | No | Polling interval in seconds | `60` |
| `PUEUE_PARALLEL` | No | Number of parallel tasks | `2` |

## Setup

### Initial Setup

```bash
git clone https://github.com/takoh/flowgate && cd flowgate
./init.sh owner/repo
```

The init script will:
1. Check Docker prerequisites
2. Build and start the container
3. Authenticate with GitHub (device code flow)
4. Authenticate with Claude (OAuth)
5. Clone the target repository

### Re-authentication

```bash
# Re-authenticate only
./init.sh --reauth

# Full reset
./init.sh --reset owner/repo
```

## Volumes

| Path | Purpose |
|------|---------|
| `~/.claude` | Claude authentication |
| `~/.config/gh` | GitHub authentication |
| `./repos` | Working repository |
| `pueue-data` | pueue state |

## Troubleshooting

### Authentication Expired

If Claude or GitHub authentication expires:

```bash
# Re-authenticate GitHub
docker exec -it flowgate gh auth login --web

# Re-authenticate Claude
docker exec -it flowgate claude login
```

### Task Not Starting

1. Check if the label is correctly applied (`flowgate`, `flowgate:swarm`, or `flowgate:hive`)
2. Verify the watcher is running:
   ```bash
   docker exec flowgate pueue status
   ```
3. Check logs:
   ```bash
   docker logs flowgate
   ```

### Queue Issues

```bash
# View queue status
docker exec flowgate pueue status

# View task logs
docker exec flowgate pueue log <task-id>

# Clear failed tasks
docker exec flowgate pueue clean
```

### Container Not Running

```bash
# Check container status
docker compose ps

# Restart container
docker compose restart

# View container logs
docker compose logs -f
```

## Limitations

- Initial setup requires manual `claude login` and `gh auth login`
- Claude authentication tokens may expire and require re-authentication
- One container = one repository (by design)

## License

[LICENSE placeholder]
