# Ubuntu SSH + Claude Code workstation (Railway template)
#
# Hardening posture:
#   - Base image pinned by digest (ubuntu:24.04)
#   - Claude Code CLI pinned to an exact version
#   - SSH is public-key only; passwords and root login are unconditionally disabled
#   - The box runs as non-root user `dev`; secrets are injected at boot, never baked in

# ubuntu:24.04 — verify/update with: docker manifest inspect ubuntu:24.04
FROM ubuntu@sha256:224a1869083a311ef3f13648a154ba79832fbef6364d31493642ca03082da254

ARG CLAUDE_CODE_VERSION=2.1.268
ARG NODE_MAJOR=22

ENV DEBIAN_FRONTEND=noninteractive

# Workstation baseline + OpenSSH server
RUN apt-get update && apt-get install -y --no-install-recommends \
        openssh-server \
        ca-certificates \
        curl \
        wget \
        git \
        jq \
        ripgrep \
        tmux \
        neovim \
        unzip \
        zip \
        locales \
        procps \
        iproute2 \
        sudo \
        gnupg \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen \
    && locale-gen \
    && update-locale LANG=en_US.UTF-8

# Node.js (pinned major) — runtime for the Claude Code CLI
RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI — exact version pin, installed system-wide so the
# /home/dev volume can never shadow or remove it.
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
    && npm cache clean --force \
    && claude --version

# Non-root login user (frees uid 1000 by removing the base image's default
# `ubuntu` user first). Password locked ('*'): no password exists to brute-force;
# authentication is possible only via authorized_keys.
RUN if id -u 1000 >/dev/null 2>&1; then userdel --remove "$(id -nu 1000)"; fi \
    && useradd --uid 1000 --create-home --shell /bin/bash dev \
    && usermod -p '*' dev \
    && echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev \
    && chmod 440 /etc/sudoers.d/dev

# SSH hardening. SetEnv lines (Claude auth passthrough) are appended at
# boot by docker-entrypoint.sh as 50-claude-env.conf.
COPY sshd-hardening.conf /etc/ssh/sshd_config.d/99-hardening.conf

# Login banner shown on every SSH session
COPY motd /etc/motd

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 755 /usr/local/bin/docker-entrypoint.sh

EXPOSE 22

CMD ["/usr/local/bin/docker-entrypoint.sh"]
