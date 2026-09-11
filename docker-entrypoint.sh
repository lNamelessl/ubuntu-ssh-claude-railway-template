#!/usr/bin/env bash
# First-boot + every-boot entrypoint for the Ubuntu SSH + Claude Code workstation.
#
# Responsibilities:
#   1. Prepare /home/dev (the Railway volume may start empty and shadow image content)
#   2. Keep SSH host keys stable across redeploys (persisted on the volume)
#   3. Install authorized_keys from the SSH_PUBLIC_KEY variable (validated)
#   4. Pass optional Claude auth variables into SSH sessions (sshd SetEnv)
#   5. Run sshd in the foreground with a lightweight watchdog
#
# Security stance: if no usable public key is available (neither from the
# variable nor already on the volume), sshd is NOT started and nothing is
# exposed. The container stays up in "safe mode" with instructions in the
# logs — it never falls back to password authentication.

set -uo pipefail

DEV_USER="dev"
DEV_HOME="/home/dev"
AUTH_KEYS="${DEV_HOME}/.ssh/authorized_keys"
HOSTKEY_DIR="${DEV_HOME}/.hostkeys"   # lives on the volume
ENV_CONF="/etc/ssh/sshd_config.d/50-claude-env.conf"
SSH_PORT="22"

log() { echo "[entrypoint] $*"; }

# --------------------------------------------------------------------------
# 1. Home directory
# --------------------------------------------------------------------------
mkdir -p "${DEV_HOME}/projects" "${DEV_HOME}/.ssh"
for f in .bashrc .profile; do
    [ -e "${DEV_HOME}/${f}" ] || cp "/etc/skel/${f}" "${DEV_HOME}/${f}" 2>/dev/null || true
done
chown -R "${DEV_USER}:${DEV_USER}" "${DEV_HOME}"

# --------------------------------------------------------------------------
# 2. SSH host keys — persisted on the volume so the host identity (and your
#    local known_hosts entry) survives redeploys.
# --------------------------------------------------------------------------
mkdir -p "${HOSTKEY_DIR}"
if [ -n "$(ls -A "${HOSTKEY_DIR}" 2>/dev/null)" ]; then
    cp -f "${HOSTKEY_DIR}"/ssh_host_* /etc/ssh/ 2>/dev/null || true
    log "restored SSH host keys from ${HOSTKEY_DIR}"
fi
ssh-keygen -A >/dev/null
cp -f /etc/ssh/ssh_host_* "${HOSTKEY_DIR}/" 2>/dev/null || true
chown -R root:root "${HOSTKEY_DIR}"
chmod 700 "${HOSTKEY_DIR}"
chmod 600 "${HOSTKEY_DIR}"/* 2>/dev/null || true

# --------------------------------------------------------------------------
# 3. authorized_keys from the SSH_PUBLIC_KEY variable.
#    Accepts one key per line; tolerates literal '\n', ';'-separated values,
#    stray quotes, comments, and blank lines. Every line is validated: it must
#    contain a recognized key type followed by a base64 blob.
# --------------------------------------------------------------------------
normalize_public_keys() {
    printf '%s' "${SSH_PUBLIC_KEY:-}" \
        | tr -d '\r' \
        | sed -e 's/\\n/\n/g' -e 's/;/\n/g' -e "s/'//g" -e 's/"//g' \
        | grep -Ev '^[[:space:]]*(#|$)'
}

KEY_LINE_RE='(^|[[:space:],])(ssh-(rsa|ed25519)|ecdsa-sha2-[a-zA-Z0-9@.-]+|sk-(ssh|ecdsa)-[a-zA-Z0-9@.-]+)[[:space:]]+[A-Za-z0-9+/]{40,}'

valid_keys="$(normalize_public_keys | grep -E "${KEY_LINE_RE}" || true)"
n_valid="$(printf '%s' "${valid_keys}" | grep -c . || true)"

if [ -n "${SSH_PUBLIC_KEY:-}" ] && [ "${n_valid}" -ge 1 ]; then
    printf '%s\n' "${valid_keys}" > "${AUTH_KEYS}"
    chown "${DEV_USER}:${DEV_USER}" "${AUTH_KEYS}"
    chmod 600 "${AUTH_KEYS}"
    log "installed ${n_valid} public key(s) from SSH_PUBLIC_KEY into authorized_keys"
elif [ -s "${AUTH_KEYS}" ]; then
    log "SSH_PUBLIC_KEY unset or invalid; keeping existing authorized_keys from the volume"
    chmod 600 "${AUTH_KEYS}"
    chown "${DEV_USER}:${DEV_USER}" "${AUTH_KEYS}"
else
    # Safe mode: refuse unauthenticated exposure. No sshd, no crash-loop.
    log "******************************************************************"
    log "SSH_PUBLIC_KEY is not set (or contains no valid public key)."
    log "Password authentication is disabled by design, so SSH will NOT start."
    log "Fix: add your public key as a Railway variable, then redeploy:"
    log "  1. On your machine:  cat ~/.ssh/id_ed25519.pub   (or id_rsa.pub)"
    log "  2. Railway -> your service -> Variables -> New Variable"
    log "     Name:  SSH_PUBLIC_KEY"
    log "     Value: <contents of the .pub file, one line>"
    log "  3. Redeploy. Nothing was exposed while this was missing."
    log "******************************************************************"
    trap 'log "safe mode: stopping"; exit 0' TERM INT
    while :; do sleep 3600 & wait $!; done
fi

# --------------------------------------------------------------------------
# 4. Claude auth passthrough. Container env vars do not reach SSH sessions
#    (sshd sanitizes the environment), so present vars are written to a
#    root-readable-only SetEnv include. All are optional: the box is
#    SSH-reachable without any of them; Claude activates when one is present.
#    NOTE: sshd honors a single SetEnv directive — all variables must share
#    one line.
# --------------------------------------------------------------------------
: > "${ENV_CONF}"
chmod 600 "${ENV_CONF}"
setenv_line=""
for v in ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_MODEL ANTHROPIC_SMALL_FAST_MODEL; do
    val="$(printf '%s' "${!v:-}" | tr -d '\r\n' | xargs 2>/dev/null || true)"
    if [ -n "${val}" ]; then
        case "${val}" in
            *[[:space:]]*)
                log "WARNING: ${v} contains whitespace; skipping SetEnv injection"
                ;;
            *)
                setenv_line="${setenv_line} ${v}=${val}"
                log "will inject ${v} into SSH sessions"
                ;;
        esac
    fi
done
if [ -n "${setenv_line}" ]; then
    printf 'SetEnv%s\n' "${setenv_line}" >> "${ENV_CONF}"
else
    log "no Claude auth variables set - SSH works; set ANTHROPIC_API_KEY later to activate Claude"
fi

# --------------------------------------------------------------------------
# 5. Run sshd in the foreground with a watchdog. If sshd dies or stops
#    listening, the container exits non-zero so Railway restarts it.
# --------------------------------------------------------------------------
mkdir -p /run/sshd
if ! /usr/sbin/sshd -t; then
    log "FATAL: sshd config test failed"
    exit 1
fi

/usr/sbin/sshd -D -e -p "${SSH_PORT}" &
SSHD_PID=$!

stop() { kill "${SSHD_PID}" 2>/dev/null; wait "${SSHD_PID}" 2>/dev/null; exit 0; }
trap stop TERM INT

log "sshd running (pid ${SSHD_PID}) on port ${SSH_PORT} - key-only auth, user '${DEV_USER}'"
log "connect with: ssh -p <TCP_PROXY_PORT> ${DEV_USER}@<TCP_PROXY_HOST>"
log "  host/port: Railway -> service -> Settings -> Networking -> TCP Proxy (auto-provisioned by this template)"

while kill -0 "${SSHD_PID}" 2>/dev/null; do
    sleep 30
    if ! ss -tln 2>/dev/null | grep -q ":${SSH_PORT} "; then
        log "sshd is not listening on port ${SSH_PORT} - restarting container"
        kill "${SSHD_PID}" 2>/dev/null
        exit 1
    fi
done

log "sshd exited unexpectedly - container will restart"
exit 1
