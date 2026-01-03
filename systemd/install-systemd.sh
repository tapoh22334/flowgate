#!/bin/bash
# flowgate systemd unit installer
# ユーザーレベルのsystemdユニットをインストールします

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

echo "flowgate systemd installer"
echo "=========================="
echo

# systemdユーザーディレクトリを作成
mkdir -p "$SYSTEMD_USER_DIR"

# ユニットファイルをコピー
echo "[1/3] Installing unit files..."
cp "$SCRIPT_DIR/flowgate.service" "$SYSTEMD_USER_DIR/"
cp "$SCRIPT_DIR/flowgate.timer" "$SYSTEMD_USER_DIR/"
echo "  -> Copied to $SYSTEMD_USER_DIR/"

# daemon-reload
echo "[2/3] Reloading systemd daemon..."
systemctl --user daemon-reload
echo "  -> Done"

# 有効化手順を表示
echo "[3/3] Installation complete!"
echo
echo "Next steps:"
echo "  # Enable and start the timer"
echo "  systemctl --user enable --now flowgate.timer"
echo
echo "  # Check status"
echo "  systemctl --user status flowgate.timer"
echo "  systemctl --user list-timers"
echo
echo "  # View logs"
echo "  journalctl --user -u flowgate -f"
echo "  tail -f ~/.flowgate/logs/watcher.log"
