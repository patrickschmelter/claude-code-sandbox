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
    zsh \
    make \
    build-essential \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libxml2-dev \
    libxmlsec1-dev \
    libffi-dev \
    liblzma-dev \
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

# Terraform
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg \
        | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
        | tee /etc/apt/sources.list.d/hashicorp.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends terraform \
    && rm -rf /var/lib/apt/lists/*

# AWS CLI
RUN ARCH="$(dpkg --print-architecture)" && \
    if [ "$ARCH" = "amd64" ]; then AWS_ARCH="x86_64"; else AWS_ARCH="aarch64"; fi && \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip

# Azure CLI
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash \
    && rm -rf /var/lib/apt/lists/*

# Sudo access: full sudo for node + NOPASSWD for firewall script
# env_keep: Pass FIREWALL_ENABLED through sudo so the toggle works
RUN printf 'Defaults:node env_keep += "FIREWALL_ENABLED"\nnode ALL=(ALL) ALL\nnode ALL=(ALL) NOPASSWD: /usr/local/bin/init-firewall.sh\n' \
        > /etc/sudoers.d/node-firewall \
    && chmod 0440 /etc/sudoers.d/node-firewall

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Firewall and entrypoint scripts
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
COPY allowed-domains.txt /usr/local/bin/allowed-domains.txt
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/init-firewall.sh /usr/local/bin/entrypoint.sh

# Default password for node user
RUN echo "node:change-me" | chpasswd

# Directories for node user
RUN mkdir -p /home/node/shared /home/node/.claude /workspace \
    && chown -R node:node /home/node/shared /home/node/.claude /workspace

# Zsh + Oh-My-Zsh (root)
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
    && chsh -s /bin/zsh root \
    && chsh -s /bin/zsh node
COPY .zshrc /root/.zshrc
COPY .zshrc /etc/skel/.zshrc

ENV DEVCONTAINER=true
ENV NODE_OPTIONS=--max-old-space-size=4096
ENV NVM_DIR=/home/node/.nvm
ENV BUN_INSTALL=/home/node/.bun

USER node

# Install nvm, Node.js 22, and Bun
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash \
    && . "$NVM_DIR/nvm.sh" \
    && nvm install 22 \
    && nvm alias default 22 \
    && curl -fsSL https://bun.sh/install | bash \
    && echo '. "$NVM_DIR/nvm.sh"' >> ~/.bashrc \
    && echo 'export PATH="$BUN_INSTALL/bin:$PATH"' >> ~/.bashrc \
    && echo '. "$NVM_DIR/nvm.sh"' >> ~/.profile \
    && echo 'export PATH="$BUN_INSTALL/bin:$PATH"' >> ~/.profile \
    && echo 'export PATH="$HOME/.jenv/bin:$PATH"' >> ~/.bashrc \
    && echo 'export PATH="$HOME/.jenv/bin:$PATH"' >> ~/.profile

# pyenv
RUN curl https://pyenv.run | bash \
    && echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc \
    && echo '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc \
    && echo 'eval "$(pyenv init - bash)"' >> ~/.bashrc \
    && echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.profile \
    && echo '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.profile \
    && echo 'eval "$(pyenv init - bash)"' >> ~/.profile

# jenv
RUN git clone https://github.com/jenv/jenv.git ~/.jenv

# context-mode plugin for Claude Code
RUN npm install -g context-mode \
    && context-mode upgrade --platform claude-code

# Oh-My-Zsh for node user + zshrc
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
COPY --chown=node:node .zshrc /home/node/.zshrc

ENV PATH=/home/node/.bun/bin:$PATH

WORKDIR /workspace

CMD ["zsh"]
