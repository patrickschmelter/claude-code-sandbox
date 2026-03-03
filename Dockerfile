FROM node:20-bookworm

ARG CLAUDE_CODE_VERSION=latest
ARG DELTA_VERSION=0.18.2

# System packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    sudo \
    procps \
    man-db \
    jq \
    unzip \
    gnupg2 \
    ca-certificates \
    curl \
    nano \
    vim \
    fzf \
    gosu \
    iptables \
    ipset \
    iproute2 \
    dnsutils \
    aggregate \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /usr/lib/python*/EXTERNALLY-MANAGED

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# git-delta (architecture detection for amd64/arm64)
RUN ARCH="$(dpkg --print-architecture)" && \
    if [ "$ARCH" = "amd64" ]; then \
        DELTA_ARCH="x86_64-unknown-linux-gnu"; \
    elif [ "$ARCH" = "arm64" ]; then \
        DELTA_ARCH="aarch64-unknown-linux-gnu"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    curl -fsSL "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-${DELTA_ARCH}.tar.gz" \
        | tar -xz -C /tmp && \
    mv "/tmp/delta-${DELTA_VERSION}-${DELTA_ARCH}/delta" /usr/local/bin/delta && \
    rm -rf /tmp/delta-*

# Sudo access ONLY for firewall script (for Dev Container postStartCommand)
# env_keep: Pass FIREWALL_ENABLED through sudo so the toggle works
RUN printf 'Defaults:node env_keep += "FIREWALL_ENABLED"\nnode ALL=(ALL) NOPASSWD: /usr/local/bin/init-firewall.sh\n' \
        > /etc/sudoers.d/node-firewall \
    && chmod 0440 /etc/sudoers.d/node-firewall

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Firewall and entrypoint scripts
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
COPY allowed-domains.txt /usr/local/bin/allowed-domains.txt
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/init-firewall.sh /usr/local/bin/entrypoint.sh

# Directories for node user
RUN mkdir -p /home/node/shared /home/node/.claude /workspace \
    && chown -R node:node /home/node/shared /home/node/.claude /workspace

ENV DEVCONTAINER=true
ENV NODE_OPTIONS=--max-old-space-size=4096

USER node
WORKDIR /workspace

CMD ["bash"]
