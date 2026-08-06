#!/bin/sh
# Authenticate the gh CLI from the host's GitHub credential.
#
# The Dev Containers extension installs a git credential helper in the container
# that answers credential requests over IPC from the host. Where the host has run
# `gh auth setup-git`, gh IS the host's git credential helper — so what comes back
# is the host's own gh token, fetched live rather than copied.
#
# gh does not consume git credential helpers for its own auth (the integration
# runs the other way: `gh auth setup-git` makes git use gh), so nothing bridges
# these on its own. This script is that bridge, run on every attach.
#
# The point is that the container holds no credential of its own: a container-local
# `gh auth login` is a point-in-time snapshot that shadows this delegation and then
# silently rots when the host's token changes.
#
# NEVER exits non-zero. A Feature's failing lifecycle hook halts the entire
# sequence — every later Feature's hooks and the project's own — so a missing
# helper or a rejected token warns and stands down.
set -u

hostname_opt="github.com"
override_existing="true"
config="$(dirname "$0")/config"
# shellcheck source=/dev/null
[ -r "$config" ] && . "$config"

warn() { echo "gh-auth-from-host: $*" >&2; }

command -v gh  >/dev/null 2>&1 || { warn "gh is not installed — skipping";  exit 0; }
command -v git >/dev/null 2>&1 || { warn "git is not installed — skipping"; exit 0; }

# Respect a deliberately-provisioned container credential when asked to.
if [ "$override_existing" != "true" ] &&
   gh auth status --hostname "$hostname_opt" >/dev/null 2>&1; then
  exit 0
fi

# `timeout` is absent from some minimal images; degrade to a bare call there.
if command -v timeout >/dev/null 2>&1; then
  fill() { timeout 30 git "$@" credential fill 2>/dev/null; }
else
  fill() { git "$@" credential fill 2>/dev/null; }
fi

# Ask the host for the credential with gh's OWN helper excluded, so the question
# can only be answered by the host.
#
# `gh auth setup-git` — which a contributor may well have run inside the
# container — installs gh as git's credential helper, and the config section it
# writes OPENS WITH AN EMPTY `helper =`, which resets the helper list and so
# wipes the editor's forwarded helper for this host. A plain `git credential
# fill` then returns gh's own stored token; the comparison below matches it; and
# this hook reports success while the stale container credential quietly
# survives — exactly the rot it exists to prevent.
#
# So rebuild the list explicitly: reset the generic and host-scoped keys (later
# -c options win), then re-add every configured helper that isn't gh. If that
# leaves nothing, the host genuinely has no helper here and we say so, rather
# than accepting gh's own answer as if it came from the host.
helpers="$( { git config --get-all credential.helper
              git config --get-all "credential.https://${hostname_opt}.helper"
            } 2>/dev/null | grep -v 'auth git-credential' | grep -v '^[[:space:]]*$' )" || true

set -- -c credential.helper= -c "credential.https://${hostname_opt}.helper="
saved_ifs=$IFS
IFS='
'
for helper in $helpers; do set -- "$@" -c "credential.helper=$helper"; done
IFS=$saved_ifs

token="$(printf 'protocol=https\nhost=%s\n\n' "$hostname_opt" | fill "$@" | awk -F= '/^password=/{print $2}')" || token=""

if [ -z "$token" ]; then
  # Legitimately absent when not attached from an editor that forwards
  # credentials (devcontainer CLI, bare docker exec), or when the host never ran
  # `gh auth setup-git`. Leave whatever gh already has alone.
  warn "host offered no credential for ${hostname_opt} — leaving gh as-is."
  warn "  (attach via VS Code, or run 'gh auth setup-git' on the HOST — note that"
  warn "   running it in the CONTAINER cannot satisfy this: gh is excluded here.)"
  exit 0
fi

# Already holding exactly what the host offers: skip the config rewrite.
current="$(gh auth token --hostname "$hostname_opt" 2>/dev/null || true)"
[ "$current" = "$token" ] && exit 0

if printf '%s\n' "$token" | gh auth login --hostname "$hostname_opt" --git-protocol https --with-token 2>/dev/null; then
  echo "gh-auth-from-host: authenticated to ${hostname_opt} from the host credential"
else
  warn "${hostname_opt} rejected the host's credential — check 'gh auth status' on the host"
fi

exit 0
