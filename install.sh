#!/bin/bash
# One-time install of the mdops portal on this Mac. Safe to re-run (idempotent).
#   git clone -b mdops-portal https://github.com/1ssb/ANU-Cluster.git ~/ANU-Cluster && ~/ANU-Cluster/install.sh
# What it changes (and nothing else):
#   1. ~/.ssh/config gets ONE line at the top: Include ~/.ssh/config.d/matterdoor.conf  (backup kept)
#   2. ~/.ssh/cm/ (connection sockets) and ~/.ssh/config.d/ are created
#   3. ~/bin/mdops -> this checkout; ~/bin added to PATH in ~/.zshrc if missing
#   4. runs `mdops discover` (read-only scan of this Mac, rudra, the cluster)
#   5. installs the keepalive LaunchAgent (undo: mdops keepalive uninstall)
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
ts=$(date +%Y%m%d-%H%M%S)
echo "== mdops install from $ROOT"
mkdir -p "$HOME/.ssh/cm" "$HOME/.ssh/config.d" "$ROOT/config" "$ROOT/state"
chmod 700 "$HOME/.ssh" "$HOME/.ssh/cm"
touch "$HOME/.ssh/config"; chmod 600 "$HOME/.ssh/config"
LINE='Include ~/.ssh/config.d/matterdoor.conf'
if ! grep -qF "$LINE" "$HOME/.ssh/config"; then
  cp "$HOME/.ssh/config" "$HOME/.ssh/config.bak.mdops.$ts"
  { echo "# mdops portal: defines md-* hosts only (remove this line + the next to undo)"; echo "$LINE"; echo; cat "$HOME/.ssh/config.bak.mdops.$ts"; } > "$HOME/.ssh/config"
  echo "+ added Include to ~/.ssh/config (backup: ~/.ssh/config.bak.mdops.$ts)"
fi
mkdir -p "$HOME/bin"; ln -sfn "$ROOT/bin/mdops" "$HOME/bin/mdops"; echo "+ ~/bin/mdops -> $ROOT/bin/mdops"
if [ -f "$HOME/.zshrc" ] || [ "${SHELL##*/}" = zsh ]; then
  grep -qE '(\$HOME|~)/bin' "$HOME/.zshrc" 2>/dev/null || { printf '\n# mdops\nexport PATH="$HOME/bin:$PATH"\n' >> "$HOME/.zshrc"; echo "+ added ~/bin to PATH in ~/.zshrc (open a new terminal)"; }
fi
export PATH="$HOME/bin:$PATH"
[ "$1" = --no-discover ] || "$ROOT/bin/mdops" discover
if [ "$(uname)" = Darwin ] && [ -f "$ROOT/config/hosts.conf" ]; then "$ROOT/bin/mdops" keepalive install || true; fi
[ -f "$ROOT/config/hosts.conf" ] && "$ROOT/bin/mdops" doctor || true
echo; echo "Installed. Agents: read $ROOT/AGENTS.md. Humans: 'mdops help', 'mdops open rudra'."
