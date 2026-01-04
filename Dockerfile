# flowgate - GitHub Issue to claude-flow task execution
# Base: Ubuntu 24.04
#
# PREREQUISITES: This image requires the following tools to be pre-installed
# on the base image or mounted at runtime:
# - Node.js 20+
# - npm
# - git
# - gh (GitHub CLI)
# - pueue/pueued
# - claude-code (@anthropic-ai/claude-code)
# - claude-flow
#
# For security reasons, this Dockerfile does NOT install dependencies.
# Users are responsible for ensuring all prerequisites are available.

FROM ubuntu:24.04

LABEL maintainer="flowgate"
LABEL description="Bridge GitHub Issues to claude-flow task execution via pueue"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# ============================================
# Directory Structure
# ============================================
# /repos   - Repository working directory
# /scripts - flowgate scripts
# /root/.pueue - pueue state (can be mounted as volume)
RUN mkdir -p /repos /scripts /root/.pueue

# ============================================
# Environment Variables
# ============================================
ENV GITHUB_REPO=""
ENV FLOWGATE_MODE="swarm"
ENV POLL_INTERVAL="60"
ENV PUEUE_PARALLEL="2"

# Set PATH to include npm global bin
ENV PATH="/usr/local/bin:/root/.npm-global/bin:${PATH}"

# ============================================
# Working Directory
# ============================================
WORKDIR /repos

# ============================================
# Copy Scripts
# ============================================
COPY scripts/flowgate.sh /usr/local/bin/flowgate
COPY scripts/flowgate-watcher.sh /usr/local/bin/flowgate-watcher
RUN chmod +x /usr/local/bin/flowgate /usr/local/bin/flowgate-watcher

# ============================================
# Entrypoint
# The entrypoint script will:
# 1. Start pueued daemon
# 2. Configure pueue parallelism
# 3. Start cron for flowgate-watcher
# 4. Keep container running
# ============================================
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# Health check for container monitoring
HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD pueue status >/dev/null 2>&1 && pgrep cron >/dev/null || exit 1

# Default command (can be overridden)
CMD ["bash"]
