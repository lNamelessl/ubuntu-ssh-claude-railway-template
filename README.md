# Ubuntu SSH + Claude Code — persistent AI workstation for Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/ubuntu-ssh-claude-workstation)

A persistent Ubuntu 24.04 box on Railway you SSH into with **your own key**, with the
**Claude Code CLI preinstalled**, and a **home volume** so your projects, tools, and Claude
sessions survive every redeploy.

- **Key-only SSH** — paste your public key as a variable at deploy time. Passwords and root
  login are disabled in the image; there is no `ROOT_PASSWORD` to leak or forget.
- **Persistent by default** — a volume is mounted at `/home/dev`. Workspaces, `~/.claude`
  (sessions, settings), installed tools, and even the SSH host keys live there, so redeploys
  don't lock you out or reset anything.
- **Claude Code ready** — the CLI is pinned and installed system-wide. Authenticate with an
  Anthropic API key, an OpenRouter key, or your Claude subscription.
- **No required secrets besides your key** — the box boots and is SSH-reachable with zero
  Anthropic credentials; Claude activates whenever you add one.

## Quick start (3 steps)

1. **Add your key** — on the deploy form, set `SSH_PUBLIC_KEY` to the contents of your
   `~/.ssh/id_ed25519.pub` (one line, starts with `ssh-ed25519`, `ssh-rsa`, `ecdsa-`, or `sk-`).
   No key yet? `ssh-keygen -t ed25519` creates one.
2. **Deploy** — the button above provisions the service, the `/home/dev` volume, and a TCP
   proxy for SSH.
3. **SSH in** — find the proxy host/port under *service → Settings → Networking → TCP Proxy*
   (format `xxx.proxy.rlwy.net:12345`), then:

   ```bash
   ssh -p 12345 dev@xxx.proxy.rlwy.net
   claude --version
   ```

## Variables

| Variable | Required | Purpose |
|---|---|---|
| `SSH_PUBLIC_KEY` | **Yes** | Your public key(s), one per line. Written to `authorized_keys` at boot. Without it, SSH stays off (see [Security](#security-model)). |
| `ANTHROPIC_API_KEY` | No | Anthropic API key (Console). Claude Code uses it automatically, no login prompt. |
| `ANTHROPIC_AUTH_TOKEN` | No | Bearer token for LLM gateways — e.g. an OpenRouter key. |
| `ANTHROPIC_BASE_URL` | No | Custom endpoint for the token above (e.g. OpenRouter). |
| `ANTHROPIC_MODEL` | No | Model override — **required for free-tier OpenRouter keys** (set a `:free` slug). `ANTHROPIC_SMALL_FAST_MODEL` does the same for Claude Code's background calls (session titles, etc.). |
| `CLAUDE_CODE_OAUTH_TOKEN` | No | Long-lived OAuth token from `claude setup-token` (Pro/Max subscription). |

All variables are optional except `SSH_PUBLIC_KEY`, and all of them can be added or changed
**after** deploying — the entrypoint re-reads them on every boot. Change a variable, redeploy,
done.

## Giving Claude Code credentials

Pick one. All of them are injected into your SSH sessions automatically when set as Railway
variables (the entrypoint writes them to an sshd `SetEnv` include — nothing is baked into the
image).

1. **Anthropic API key** — set `ANTHROPIC_API_KEY=sk-ant-...` and redeploy. In headless
   mode (`claude -p "..."`) the key is used with no prompt.
2. **OpenRouter** — set:
   - `ANTHROPIC_AUTH_TOKEN=sk-or-v1-...`
   - `ANTHROPIC_BASE_URL=https://openrouter.ai/api` (OpenRouter's Anthropic-compatible endpoint)
   - `ANTHROPIC_MODEL=<slug>` — strongly recommended; see the free-tier note below. Set
     `ANTHROPIC_SMALL_FAST_MODEL` to the same slug to route background calls (session
     titles, etc.) to the same place.

   **Free-tier OpenRouter keys** (under $10 lifetime credits) hit a hard cap: prompts are
   limited to 8k tokens on paid models, and Claude Code's system prompt alone is ~18k — so
   requests fail with `402 Prompt tokens limit exceeded`. Free models (`:free` slugs) bypass
   that cap entirely: set `ANTHROPIC_MODEL` to a free general-purpose slug, e.g.
   `nvidia/nemotron-3.5-lightning:free` (1M context). Free slugs get withdrawn and added
   over time — pick a current one from [openrouter.ai/models](https://openrouter.ai/models)
   or `GET https://openrouter.ai/api/v1/models`. Expect roughly 50 requests/day per key on
   the free tier.
3. **Claude subscription (Pro/Max/Team)** — on your own machine run `claude setup-token`,
   copy the printed token, set `CLAUDE_CODE_OAUTH_TOKEN=<token>` here, redeploy.
4. **Interactive login** — just run `claude` over SSH and follow the URL (copy it into a local
   browser, paste the code back). Works fine from containers; use `/login` to renew, `/logout` to reset.

Verify with `claude` → `/status`, or non-interactively: `claude -p "Reply with exactly: OK"`.

## Persistence

The volume is mounted at `/home/dev`. Everything under it survives redeploys, restarts, and
image upgrades:

- `~/projects` — your code
- `~/.claude` — Claude Code settings, session history, project memory
- `~/.ssh/authorized_keys` — if you ever redeploy without `SSH_PUBLIC_KEY` set, your
  previously-installed keys keep working
- `~/.hostkeys` — the server's SSH host keys, so you don't get host-key-changed warnings

Outside `/home/dev` is ephemeral by design (it's a container, not a VPS): anything you
`apt install` or `npm install -g` lives until the next redeploy. `sudo` is available — use it
for throwaway tooling, keep durable work in your home.

## Resource expectations (honest numbers)

- The idle box (sshd + OS) uses ~100–200 MB RAM.
- Claude Code is comfortable at **≥1 GB** total; **2 GB** is recommended for long agentic
  sessions with big repos. Anthropic's docs advise 4 GB+ for the best experience.
- Storage: the volume starts at 0.5–1 GB (Railway minimum) — plenty for code; watch it if you
  pull datasets or models.
- Cost: an always-on box with ~1–2 GB RAM lands around **$10–20/month** on Railway usage-based
  pricing. Sleeping the service when idle cuts that substantially.

## Security model

- **Public-key auth only.** `PasswordAuthentication no`, `KbdInteractiveAuthentication no`,
  `AuthenticationMethods publickey`, `PermitRootLogin no`, `AllowUsers dev` — compiled into
  the image's sshd config, not toggleable by a forgotten variable.
- **No usable passwords exist** — the `dev` account's password field is locked (`*`). There is
  no `ROOT_PASSWORD`-style secret to brute-force, leak, or forget.
- **Refuse-unauthenticated-exposure** — if no valid public key is available (variable empty or
  malformed *and* no keys already on the volume), sshd never starts. The container stays up in
  safe mode with instructions in the logs; nothing is listening on port 22.
- **Secrets are never baked into the image.** All credentials arrive as Railway variables at
  boot; the auth passthrough file is root-owned, mode 0600.
- **Non-root** — you land as `dev` (uid 1000) with `sudo` for admin tasks. Single-user box:
  anyone with your private key *is* the admin, which is the point.
- **Pinned supply chain** — base image pinned by digest; Claude Code pinned to an exact
  version (see the `ARG` lines in the [Dockerfile](Dockerfile)).

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Deploy succeeded, logs say `SSH_PUBLIC_KEY is not set` | Safe mode. Add the variable and redeploy — the box intentionally exposes nothing without a key. |
| `Permission denied (publickey)` | The variable didn't match the private key you're using. Compare: `ssh -v -p PORT dev@HOST` should offer the right key. Re-paste the `.pub` **contents** (not the filename/path). |
| Variable rejected as invalid | Keys must be one key per line, starting with `ssh-ed25519`, `ssh-rsa`, `ecdsa-sha2-...`, or `sk-...`, followed by the base64 blob. Re-copy from `cat ~/.ssh/id_ed25519.pub`. |
| Can't find where to connect | Service → **Settings → Networking → TCP Proxy** — you need the **port** too; SSH runs on a high port (`ssh -p NNNNN`), not 22 externally. |
| `claude` returns 401 / invalid API key | Check which auth var is set (`/status` inside claude shows the active auth). For OpenRouter both `ANTHROPIC_AUTH_TOKEN` **and** `ANTHROPIC_BASE_URL` must be set. `/logout` clears stale interactive credentials. |
| `402 Prompt tokens limit exceeded` | Free-tier OpenRouter key (under $10 credits) on a **paid** model — free-tier keys cap prompts at 8k tokens, below Claude Code's ~18k system prompt. Set `ANTHROPIC_MODEL` to a `:free` slug (see [Giving Claude Code credentials](#giving-claude-code-credentials)). |
| `unrecognized_model` / model-catalog warning at startup | Benign. Claude Code doesn't recognize the third-party model id, assumes a 200k context window, and works anyway. |
| Host key warning after redeploy | You likely deleted the volume, or connected to a different project's proxy. `ssh-keygen -R "[host]:port"` clears the old entry. |
| Files gone after redeploy | They were outside `/home/dev`. Keep durable work in your home directory. |

## Updating the pins

```bash
# Base image digest
docker manifest inspect ubuntu:24.04

# Claude Code version (then edit ARG CLAUDE_CODE_VERSION in the Dockerfile)
npm view @anthropic-ai/claude-code version
```

## Repository layout

```
Dockerfile            pinned Ubuntu + Node + Claude Code + hardened sshd
docker-entrypoint.sh  first-boot credential flow, host-key persistence, sshd watchdog
sshd-hardening.conf   key-only auth, no root, AllowUsers dev
railway.json          Railway build/deploy configuration
TEMPLATE_OVERVIEW.md  marketplace listing copy
```

## License

[MIT](LICENSE)
