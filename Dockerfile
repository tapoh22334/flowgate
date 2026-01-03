# flowgate - GitHub Issue to claude-flow task execution
# Base: Ubuntu 24.04

FROM ubuntu:24.04

LABEL maintainer="flowgate"
LABEL description="Bridge GitHub Issues to claude-flow task execution via pueue"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# ============================================
# System Dependencies
# ============================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Essential tools
    ca-certificates \
    curl \
    wget \
    gnupg \
    # Git
    git \
    # Build tools (for native npm modules)
    build-essential \
    python3 \
    # Process management
    cron \
    # Utilities
    jq \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# Node.js 20 (via NodeSource)
# ============================================
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g npm@latest

# Verify Node.js installation
RUN node --version && npm --version

# ============================================
# GitHub CLI (gh)
# ============================================
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Verify gh installation
RUN gh --version

# ============================================
# pueue (Task Queue Manager)
# Install from GitHub releases (latest stable)
# ============================================
ARG PUEUE_VERSION=3.4.1
RUN ARCH=$(dpkg --print-architecture) \
    && case "${ARCH}" in \
        amd64) PUEUE_ARCH="x86_64-unknown-linux-musl" ;; \
        arm64) PUEUE_ARCH="aarch64-unknown-linux-musl" ;; \
        *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
    esac \
    && curl -fsSL "https://github.com/Nukesor/pueue/releases/download/v${PUEUE_VERSION}/pueue-linux-${PUEUE_ARCH}" \
       -o /usr/local/bin/pueue \
    && curl -fsSL "https://github.com/Nukesor/pueue/releases/download/v${PUEUE_VERSION}/pueued-linux-${PUEUE_ARCH}" \
       -o /usr/local/bin/pueued \
    && chmod +x /usr/local/bin/pueue /usr/local/bin/pueued

# Verify pueue installation
RUN pueue --version && pueued --version

# ============================================
# NPM Global Packages
# - claude-flow: Orchestration framework
# - @anthropic-ai/claude-code: Claude Code CLI
# ============================================
RUN npm install -g \
    @anthropic-ai/claude-code \
    claude-flow

# Verify installations
RUN claude --version || echo "claude-code installed" \
    && claude-flow --version || echo "claude-flow installed"

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

# Default command (can be overridden)
CMD ["bash"]
