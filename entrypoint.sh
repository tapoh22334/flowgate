#!/bin/bash
set -e

# =====================================================
# flowgate entrypoint.sh
#
# Container initialization:
# 1. Start pueued daemon (background)
# 2. Configure cron for flowgate-watcher
# 3. Start cron daemon
# 4. Keep container alive with graceful shutdown handling
# =====================================================

# Configuration
POLL_INTERVAL="${POLL_INTERVAL:-60}"
PUEUE_PARALLEL="${PUEUE_PARALLEL:-2}"

echo "=== flowgate container starting ==="
echo "POLL_INTERVAL: ${POLL_INTERVAL}s"
echo "PUEUE_PARALLEL: ${PUEUE_PARALLEL}"

# -----------------------------------------------------
# 1. Start pueued daemon
# -----------------------------------------------------
echo "[1/4] Starting pueued daemon..."

# Ensure pueue config directory exists
mkdir -p ~/.config/pueue

# Start pueued in background
pueued --daemonize 2>/dev/null || {
    # If daemonize fails, try without it
    pueued &
    sleep 1
}

# Configure parallel tasks
pueue parallel "${PUEUE_PARALLEL}" 2>/dev/null || true

echo "      pueued started (parallel: ${PUEUE_PARALLEL})"

# -----------------------------------------------------
# 2. Configure cron for flowgate-watcher
# -----------------------------------------------------
echo "[2/4] Configuring cron job..."

# Create cron job file
# Run flowgate-watcher every minute
CRON_FILE="/etc/cron.d/flowgate"

cat > "${CRON_FILE}" << EOF
# flowgate-watcher cron job
# Runs every minute to check for new issues with flowgate labels
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

* * * * * root /usr/local/bin/flowgate-watcher >> /var/log/flowgate-watcher.log 2>&1
EOF

# Set proper permissions for cron file
chmod 0644 "${CRON_FILE}"

# Create log file
touch /var/log/flowgate-watcher.log
chmod 0644 /var/log/flowgate-watcher.log

echo "      cron job configured (every minute)"

# -----------------------------------------------------
# 3. Start cron daemon
# -----------------------------------------------------
echo "[3/4] Starting cron daemon..."

# Start cron daemon
cron

echo "      cron daemon started"

# -----------------------------------------------------
# 4. Graceful shutdown handling
# -----------------------------------------------------
echo "[4/4] Setting up signal handlers..."

# Graceful shutdown function
shutdown() {
    echo ""
    echo "=== Shutting down flowgate container ==="

    # Stop cron
    echo "Stopping cron..."
    pkill cron 2>/dev/null || true

    # Stop pueue tasks and daemon
    echo "Stopping pueue..."
    pueue kill --all 2>/dev/null || true
    pueue shutdown 2>/dev/null || true

    echo "Shutdown complete"
    exit 0
}

# Trap signals for graceful shutdown
trap shutdown SIGTERM SIGINT SIGHUP

echo ""
echo "=== flowgate container ready ==="
echo "Watching for GitHub issues with 'flowgate' labels..."
echo ""

# -----------------------------------------------------
# Keep container alive
# -----------------------------------------------------
# Use tail -f /dev/null with wait to allow signal handling
tail -f /dev/null &
TAIL_PID=$!

# Wait for the tail process, allowing signals to be caught
wait $TAIL_PID
