#!/bin/sh
# Runs as root at image build time. Installs the refresh script and bakes the
# Feature's options into a config file beside it — the postAttachCommand runs as
# the remote user, long after these build-time env vars are gone.
set -eu

TARGET_DIR="/usr/local/share/gh-auth-from-host"

install -d -m 0755 "$TARGET_DIR"
install -m 0755 "$(dirname "$0")/refresh.sh" "$TARGET_DIR/refresh.sh"

# Option env vars are uppercased by the Feature installer; defaults here mirror
# devcontainer-feature.json so a direct invocation still works. NB the option is
# githubHostname, not hostname — HOSTNAME is already the container's own hostname
# and would quietly win here.
gh_host="${GITHUBHOSTNAME:-github.com}"
override="${OVERRIDEEXISTING:-true}"

cat > "$TARGET_DIR/config" <<EOF
hostname_opt="${gh_host}"
override_existing="${override}"
EOF
chmod 0644 "$TARGET_DIR/config"

echo "gh-auth-from-host: installed to $TARGET_DIR (host=${gh_host}, overrideExisting=${override})"
