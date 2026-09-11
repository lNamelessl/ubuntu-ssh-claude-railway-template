# Ubuntu SSH + Claude Code — Persistent AI Workstation

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/ubuntu-ssh-claude-workstation)

A persistent Ubuntu 24.04 workstation on Railway that you reach over **SSH with your own key**, with the **Claude Code CLI preinstalled** and a **home volume** that survives every redeploy. Deploy it, SSH in, and start working with Claude in under a minute.

## What you get

- **Key-only SSH access** — set `SSH_PUBLIC_KEY` to your public key on the deploy form and connect with `ssh -p PORT dev@HOST`. Password authentication and root login are disabled in the image itself; there is no root password to leak, brute-force, or forget.
- **Claude Code, ready** — the CLI is pinned, installed system-wide, and on PATH the moment you log in. Bring credentials your way: an Anthropic API key, an OpenRouter key, a long-lived subscription token, or an interactive `/login` over SSH.
- **Persistence that actually persists** — a volume mounted at `/home/dev` keeps your projects, tools, Claude sessions (`~/.claude`), and even the server's SSH host keys across redeploys and restarts. No host-key-changed warnings, no lost work.
- **Refuse-to-expose safety** — if no valid public key is configured, SSH simply does not start. The container stays up with clear instructions in the logs and nothing listening on port 22. It never falls back to passwords.
- **A real Linux box** — Ubuntu 24.04 (pinned by digest) with git, tmux, neovim, ripgrep, jq, Node 22, and `sudo`. Run anything you'd run on a cloud dev box.

## Setup in 3 steps

1. **Add your key** — on the deploy form, paste the contents of `~/.ssh/id_ed25519.pub` into `SSH_PUBLIC_KEY`. (No key yet? `ssh-keygen -t ed25519` — 5 seconds.)
2. **Deploy** — this template provisions the service, the `/home/dev` volume, and the TCP proxy automatically.
3. **SSH in** — copy the host/port from *Settings → Networking → TCP Proxy* and run `ssh -p PORT dev@HOST`. Run `claude` to start.

## Cost & resources

The idle box uses ~100–200 MB RAM. Claude Code is comfortable at ≥1 GB and recommends 2 GB+ for heavy agentic sessions. An always-on instance typically lands at $10–20/month on usage-based pricing. Your Anthropic/OpenRouter usage is billed by your own API provider — nothing is routed through third parties.

## Security

Key-only authentication (passwords and keyboard-interactive hard-disabled), no root login, single non-root `dev` user, credentials injected at boot from Railway variables and never baked into the image, base image digest-pinned, Claude Code version-pinned. Your API keys live in your Railway project's variables and are passed into your SSH sessions only.

# Deploy and Host

## About Hosting

Hosting this template runs one service: an Ubuntu 24.04 container with OpenSSH and the Claude Code CLI. A TCP proxy exposes SSH publicly (`xxx.proxy.rlwy.net:PORT` — the proxy port is not 22; use `ssh -p PORT`). A volume mounted at `/home/dev` persists your home directory, Claude sessions, authorized keys, and SSH host keys across redeploys. Resource-wise, expect ~100–200 MB RAM idle, 1–2 GB comfortable with Claude Code active, and roughly $10–20/month always-on on Railway's usage-based pricing.

## Why Deploy

- You want a **cloud Linux box that doesn't reset itself** — the home volume keeps code, config, and Claude session history across redeploys, which most SSH-on-Railway templates don't do.
- You want **Claude Code without local setup** — it's preinstalled, pinned, and authenticated with one variable (`ANTHROPIC_API_KEY`, OpenRouter's `ANTHROPIC_AUTH_TOKEN` + `ANTHROPIC_BASE_URL`, or `CLAUDE_CODE_OAUTH_TOKEN`).
- You want **safe defaults instead of a root password** — key-only auth is enforced in the image, and without a valid key the SSH port simply stays closed rather than opening to password guessing.
- You want an **always-on agent host** — long-running Claude sessions in tmux that survive your laptop closing, reachable from anywhere.

## Common Use Cases

- **AI pair-programming box** — SSH in from any device, run Claude Code against repos cloned into `~/projects`, keep sessions alive in tmux.
- **Persistent cloud workstation** — a familiar Ubuntu environment with your dotfiles, tools, and shell history that outlives redeploys.
- **Automation host** — run Claude Code headlessly (`claude -p`) in cron jobs or scripts from a box that's always on.
- **Sandboxed experimentation** — install packages with `sudo`, try risky commands, and redeploy for a fresh OS while your home directory survives untouched.
- **Remote development travel terminal** — a lightweight box you can reach from a tablet or borrowed machine over plain SSH.

## Dependencies for

### Deployment Dependencies

- **An SSH public key** — the only required input. Provide `SSH_PUBLIC_KEY` (contents of your `~/.ssh/id_ed25519.pub`) on the deploy form. Without it the service boots in safe mode with SSH disabled until you add one.
- **A Claude Code credential (optional at deploy time)** — activate Claude later by setting any one of: `ANTHROPIC_API_KEY` (Anthropic Console), `ANTHROPIC_AUTH_TOKEN` + `ANTHROPIC_BASE_URL` (e.g. OpenRouter), or `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`). Usage is billed by your provider.
- **An SSH client** — any OpenSSH client works: `ssh -p PORT dev@HOST` with the matching private key.
- No other services, databases, or credentials are required — the template is fully self-contained.
