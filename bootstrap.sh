#!/bin/bash
# One-time (idempotent) setup of the MatterDoor workspace on this Mac.
#   git clone -b mdops-portal https://github.com/1ssb/ANU-Cluster.git ~/MatterDoor/ANU-Cluster && ~/MatterDoor/ANU-Cluster/bootstrap.sh
# Creates ~/MatterDoor (+ ~/Desktop/MatterDoor link), clones the project repos, sets up Git + Git LFS
# and the project guards, installs the portal (mtd/mdops), runs discovery, records your backup choice.
# Never deletes anything. Data is never uploaded.
set -e
PORTAL="$(cd "$(dirname "$0")" && pwd)"
WS="${MD_WORKSPACE:-$(dirname "$PORTAL")}"
GH="${MD_GH_BASE:-https://github.com/1ssb}"
say() { printf '%s\n' "$*"; }
say "== MatterDoor workspace: $WS"
mkdir -p "$WS/scratch" "$WS/data"

# 0. an earlier install at ~/ANU-Cluster keeps its config/state
if [ -d "$HOME/ANU-Cluster/config" ] && [ "$HOME/ANU-Cluster" != "$PORTAL" ]; then
  for d in config state; do [ -d "$HOME/ANU-Cluster/$d" ] && cp -Rn "$HOME/ANU-Cluster/$d/." "$PORTAL/$d/" 2>/dev/null || true; done
  say "+ carried config/state over from ~/ANU-Cluster (the old folder is left untouched; remove it yourself when happy)"
fi

# 1. Desktop link (the real folder stays outside iCloud-synced Desktop, which corrupts git repos)
if [ "$WS" != "$HOME/Desktop/MatterDoor" ]; then
  if [ -L "$HOME/Desktop/MatterDoor" ] || [ ! -e "$HOME/Desktop/MatterDoor" ]; then ln -sfn "$WS" "$HOME/Desktop/MatterDoor"; say "+ ~/Desktop/MatterDoor -> $WS"
  else say "! ~/Desktop/MatterDoor exists and is not a link; left alone (point agents at $WS)"; fi
fi

# 2. Git + Git LFS
command -v git >/dev/null || { say "! git missing: run 'xcode-select --install' and re-run"; exit 1; }
if ! command -v git-lfs >/dev/null; then
  if command -v brew >/dev/null; then brew install git-lfs; else say "! git-lfs missing: install from https://git-lfs.com (or Homebrew) and re-run"; fi
fi
command -v git-lfs >/dev/null && git lfs install --skip-repo >/dev/null && say "+ Git LFS filters installed (user level)"

# 3. repos (your GitHub credentials; private repos need them)
clone() { # NAME BRANCH-IF-PRESENT
  local r=$1 b=$2
  if [ ! -d "$WS/$r/.git" ]; then GIT_LFS_SKIP_SMUDGE=1 git clone -q "$GH/$r.git" "$WS/$r" || { say "! could not clone $r (GitHub login?) — fix and re-run"; return 1; }; say "+ cloned $r"; fi
  if [ -n "$b" ] && git -C "$WS/$r" ls-remote --exit-code --heads origin "$b" >/dev/null 2>&1; then
    git -C "$WS/$r" fetch -q origin "$b" && { git -C "$WS/$r" checkout -q "$b" 2>/dev/null || git -C "$WS/$r" checkout -q -b "$b" --track "origin/$b"; } && say "+ $r on branch $b"
  fi
  if command -v git-lfs >/dev/null; then git -C "$WS/$r" lfs install --local >/dev/null 2>&1
    git -C "$WS/$r" lfs pull >/dev/null 2>&1 && say "+ $r LFS files fetched" || say "! $r: some LFS files not fetched (non-fatal; later: git -C $WS/$r lfs pull)"; fi
}
clone into_the_unknown matterdoor-control-plane || true
clone into_the_unknown_paper "" || true
[ -d "$WS/into_the_unknown/control/hooks" ] && git -C "$WS/into_the_unknown" config core.hooksPath control/hooks && say "+ project guards active (pre-commit / pre-push)"

# 4. workspace root files (always refreshed from the portal's templates)
cp "$PORTAL/templates/workspace/AGENTS.md" "$PORTAL/templates/workspace/README.md" "$PORTAL/templates/workspace/CLAUDE.md" "$WS/"
cp "$PORTAL/templates/workspace/data.README.md" "$WS/data/README.md"
say "+ workspace AGENTS.md / README.md / CLAUDE.md written"

# 5. portal install (ssh Include, ~/bin/mtd, discovery, agent key, handoff, keepalive)
"$PORTAL/install.sh" "$@" </dev/null   # prompts read /dev/tty; closed stdin stops ssh swallowing typed-ahead answers
MDOPS="$PORTAL/bin/mdops"; CONF="$PORTAL/config/hosts.conf"
if [ -f "$CONF" ]; then
  grep -q '^WORKSPACE=' "$CONF" || printf '\n# workspace (bootstrap)\nWORKSPACE=%q\n' "$WS" >> "$CONF"
  [ -f "$WS/into_the_unknown/control/mdops.conf" ] && "$MDOPS" profile apply "$WS/into_the_unknown/control/mdops.conf" >/dev/null && say "+ project profile applied"
  # 6. backup approval: the PI's standing choice (agents may not change it)
  if ! grep -q '^BACKUP_STANDING_APPROVAL=' "$CONF"; then
    printf 'Allow agents to back up code and documents (never data) automatically to your GitHub repos and to rudra? [y/N] '
    if [ -n "${MD_BACKUP_APPROVAL:-}" ]; then ans=$MD_BACKUP_APPROVAL; echo "$ans (from MD_BACKUP_APPROVAL)"; else read -r ans </dev/tty || ans=n; fi
    case "$ans" in y|Y|yes) v=yes;; *) v=no;; esac
    printf '\n# PI standing approval for code/doc backups (set by bootstrap %s)\nBACKUP_STANDING_APPROVAL=%s\n' "$(date '+%F %T')" "$v" >> "$CONF"
    MD_AGENT=human "$MDOPS" journal "PI set BACKUP_STANDING_APPROVAL=$v at bootstrap" >/dev/null 2>&1 || true
    say "+ backup approval: $v"
  fi
  [ "$(uname)" = Darwin ] && "$MDOPS" backup install || true
  "$MDOPS" route rudra >/dev/null 2>&1 && MD_AGENT=bootstrap "$MDOPS" env snapshot rudra || say "! rudra not reachable: env snapshot later with 'mtd env snapshot rudra'"
  "$MDOPS" check || true
fi
say ""
say "Done. Point any agent at ~/Desktop/MatterDoor (it reads AGENTS.md and runs 'mtd')."
