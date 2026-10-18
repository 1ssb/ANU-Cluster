#!/usr/bin/env bash
# mdops-remote — runs ON rudra / the cluster, streamed over ssh by bin/mdops:
#   ssh HOST bash -s -- <subcommand> [args...] < remote/mdops-remote.sh
# Never deployed, so it can never drift from the portal version.
# State lives in $MD_STATE (default ~/mdops-state): locks/, runs/, journal.md
set -uo pipefail
STATE="${MD_STATE:-$HOME/mdops-state}"
mkdir -p "$STATE/locks" "$STATE/runs" "$STATE/bin"
INDEX="$STATE/runs/INDEX.tsv"
[ -f "$INDEX" ] || printf 'run_id\thost\tkind\tname\tcommit\tdirty\tagent\tstarted\tjob\n' > "$INDEX"
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
die() { echo "mdops-remote: $*" >&2; exit 2; }

# ---------- locks: atomic mkdir, TTL, owner-checked release ----------
lock_acquire() { # NAME OWNER TTL_MIN
  local name=$1 owner=$2 ttl=${3:-120} d exp
  [[ $name =~ ^[A-Za-z0-9._-]+$ ]] || die "bad lock name"
  d="$STATE/locks/$name.lock"
  if mkdir "$d" 2>/dev/null; then
    printf 'owner=%s\nacquired=%s\nexpires_epoch=%s\nhost=%s\n' "$owner" "$(now)" $(( $(date +%s) + ttl*60 )) "$(hostname -s)" > "$d/info"
    echo "ACQUIRED $name by $owner for ${ttl}m"; return 0
  fi
  exp=$(sed -n 's/^expires_epoch=//p' "$d/info" 2>/dev/null)
  if [ -n "$exp" ] && [ "$exp" -lt "$(date +%s)" ]; then
    echo "lock $name expired (was: $(tr '\n' ' ' < "$d/info")); taking over"
    rm -rf -- "$d" && lock_acquire "$name" "$owner" "$ttl"; return $?
  fi
  echo "BUSY $name: $(tr '\n' ' ' < "$d/info" 2>/dev/null)"; return 1
}
lock_release() { # NAME OWNER [--force]
  local name=$1 owner=$2 force=${3:-} d cur
  d="$STATE/locks/$name.lock"; [ -d "$d" ] || { echo "not held: $name"; return 0; }
  cur=$(sed -n 's/^owner=//p' "$d/info" 2>/dev/null)
  if [ "$cur" != "$owner" ] && [ "$force" != --force ]; then die "lock $name is held by '$cur', not '$owner' (use --force only if the human says so)"; fi
  rm -rf -- "$d"; echo "RELEASED $name"
}
lock_list() {
  local d any=0 exp state
  for d in "$STATE"/locks/*.lock; do
    [ -d "$d" ] || continue; any=1
    exp=$(sed -n 's/^expires_epoch=//p' "$d/info" 2>/dev/null); state=held
    [ -n "$exp" ] && [ "$exp" -lt "$(date +%s)" ] && state=EXPIRED
    printf '%-24s %-8s %s\n' "$(basename "$d" .lock)" "$state" "$(tr '\n' ' ' < "$d/info" 2>/dev/null)"
  done
  [ $any = 1 ] || echo "(no locks held)"
}

# ---------- journal ----------
journal() { local agent=$1; shift; printf -- '- %s [%s@%s] %s\n' "$(now)" "$agent" "$(hostname -s)" "$*" >> "$STATE/journal.md"; echo "journaled"; }

# ---------- git provenance ----------
git_prov() { # DIR ALLOW_DIRTY RUN_DIR -> sets COMMIT DIRTY
  local dir=$1 allow=$2 rd=$3
  COMMIT=nogit; DIRTY=0
  if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    COMMIT=$(git -C "$dir" rev-parse HEAD)
    if [ -n "$(git -C "$dir" status --porcelain --untracked-files=no)" ]; then
      DIRTY=1
      [ "$allow" = 1 ] || die "repo $dir has uncommitted changes to tracked files; commit first (or pass --allow-dirty, the diff is saved)"
      mkdir -p "$rd"; git -C "$dir" diff HEAD > "$rd/dirty.patch"
    fi
  else
    [ "$allow" = 1 ] || die "$dir is not a git repo; runs must be reproducible (pass --allow-dirty to override)"
  fi
}

new_run_id() { local id; id=$(printf '%s-%s-%s' "$(date +%Y%m%d-%H%M%S)" "$1" "$2")
  [ -e "$STATE/runs/$id" ] && id="$id-$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"; printf '%s' "$id"; }

# ---------- run on this box in tmux, GPU serialised with flock ----------
run_local() { # NAME DIR ALLOW_DIRTY GPU AGENT OUT_ROOT -- CMD...
  local name=$1 dir=$2 allow=$3 gpu=$4 agent=$5 outroot=$6; shift 6; [ "${1:-}" = -- ] && shift
  [ $# -gt 0 ] || die "no command"
  [[ $name =~ ^[A-Za-z0-9._-]+$ ]] || die "bad run name"
  command -v tmux >/dev/null || die "tmux missing on $(hostname -s)"
  dir=$(cd "$dir" 2>/dev/null && pwd) || die "no such dir: $2"
  local id rd out; id=$(new_run_id "$(hostname -s)" "$name"); rd="$STATE/runs/$id"
  git_prov "$dir" "$allow" "$rd"; mkdir -p "$rd"
  if [ -n "$outroot" ]; then out="$outroot/runs/$id"; else out="$rd/out"; fi
  mkdir -p "$out" || die "cannot create $out"
  printf '%q ' "$@" > "$rd/cmd.txt"
  { echo "run_id=$id"; echo "host=$(hostname -s)"; echo "dir=$dir"; echo "commit=$COMMIT"; echo "dirty=$DIRTY"
    echo "agent=$agent"; echo "gpu_lock=$gpu"; echo "out_dir=$out"; echo "started=$(now)"; } > "$rd/meta.env"
  cat > "$rd/launch.sh" <<EOF
#!/usr/bin/env bash
cd $(printf %q "$dir") || exit 97
export MD_RUN_ID=$id MD_RUN_DIR=$(printf %q "$rd") MD_OUT_DIR=$(printf %q "$out")
{
  echo "[mdops] \$(date -Is) start \$MD_RUN_ID"
  if [ "$gpu" = 1 ]; then
    exec 9>"\${MD_GPU_LOCK:-/tmp/mdops-gpu.\$(id -u).lock}"
    echo "[mdops] waiting for GPU lock (other runs queue here, they do not collide)"
    flock 9; echo "[mdops] \$(date -Is) GPU lock acquired"
  fi
  $(cat "$rd/cmd.txt")
  rc=\$?; echo "\$rc" > "\$MD_RUN_DIR/exit_code"; echo "[mdops] \$(date -Is) exit \$rc"
} 2>&1 | tee -a "\$MD_RUN_DIR/log.txt"
EOF
  chmod +x "$rd/launch.sh"
  tmux new-session -d -s "md-$id" "bash $(printf %q "$rd/launch.sh")" || die "tmux launch failed"
  printf '%s\t%s\tlocal\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$(hostname -s)" "$name" "$COMMIT" "$DIRTY" "$agent" "$(now)" "tmux:md-$id" >> "$INDEX"
  echo "RUN $id"; echo "log: $rd/log.txt"; echo "out: $out"; echo "attach: tmux attach -t md-$id"
}

# ---------- storage usage (best effort: lustre quota > user quota > df) ----------
usage() { # PATH -> "pct used_h limit_h source"
  local p=${1/#\~/$HOME} mnt line
  [ -e "$p" ] || { echo "0 ? ? missing"; return; }
  if command -v lfs >/dev/null 2>&1 && [ "$(stat -f -c %T "$p" 2>/dev/null)" = lustre ]; then
    mnt=$(df -P "$p" | awk 'NR==2{print $6}')
    for kind in "-u $USER" "-g $(id -gn)"; do
      # shellcheck disable=SC2086
      line=$(lfs quota -q $kind "$mnt" 2>/dev/null | awk 'NF>=4{print $2, ($4>0?$4:$3)}' | head -1)
      set -- $line
      if [ -n "${2:-}" ] && [ "${2%\*}" -gt 0 ] 2>/dev/null; then
        echo "$(( ${1%\*} * 100 / ${2%\*} )) $(( ${1%\*} / 1048576 ))G $(( ${2%\*} / 1048576 ))G lustre${kind%% *}"; return
      fi
    done
  fi
  df -P "$p" | awk 'NR==2{gsub("%","",$5); printf "%s %.0fG %.0fG df\n", $5, $3/1048576, $2/1048576}'
}

# ---------- slurm submit ----------
run_slurm() { # NAME DIR ALLOW_DIRTY AGENT WORK_ROOT STOP_PCT SBATCH_ARGS... -- CMD...
  local name=$1 dir=$2 allow=$3 agent=$4 work=$5 stop=$6; shift 6
  local sb=(); while [ $# -gt 0 ] && [ "$1" != -- ]; do sb+=("$1"); shift; done; [ "${1:-}" = -- ] && shift
  [ $# -gt 0 ] || die "no command"
  [ -n "$work" ] || die "CLUSTER_WORK_ROOT not set in config/hosts.conf"
  command -v sbatch >/dev/null || die "sbatch not found on $(hostname -s)"
  dir=$(cd "$dir" 2>/dev/null && pwd) || die "no such dir: $2"
  local u; u=$(usage "$work"); [ "${u%% *}" -lt "$stop" ] || die "storage at ${u%% *}% (stop at $stop%): $u — harvest+prune first"
  local id rd out; id=$(new_run_id cluster "$name"); rd="$STATE/runs/$id"; out="$work/runs/$id"
  git_prov "$dir" "$allow" "$rd"; mkdir -p "$rd" "$out"
  printf '%q ' "$@" > "$rd/cmd.txt"
  { echo '#!/usr/bin/env bash'; echo "#SBATCH --job-name=md-$name"; echo "#SBATCH --output=$out/slurm-%j.log"
    for a in "${sb[@]}"; do echo "#SBATCH $a"; done
    echo "set -o pipefail"
    echo "cd $(printf %q "$dir") || exit 97"
    echo "export MD_RUN_ID=$id MD_RUN_DIR=$(printf %q "$rd") MD_OUT_DIR=$(printf %q "$out")"
    # keep every cache/temp OUT of the (tiny) home + login node; jobs never download
    echo "export MD_WORK=$(printf %q "$work"); export XDG_CACHE_HOME=\$MD_WORK/cache HF_HOME=\$MD_WORK/cache/hf TORCH_HOME=\$MD_WORK/cache/torch"
    echo "export PIP_CACHE_DIR=\$MD_WORK/cache/pip CONDA_PKGS_DIRS=\$MD_WORK/cache/conda-pkgs WANDB_DIR=\$MD_OUT_DIR WANDB_MODE=\${WANDB_MODE:-offline}"
    echo "export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 MPLCONFIGDIR=\$MD_WORK/cache/mpl"
    echo "export TMPDIR=\${SLURM_TMPDIR:-\${TMPDIR_LOCAL:-\$MD_WORK/tmp/\$SLURM_JOB_ID}}; mkdir -p \"\$TMPDIR\" \"\$XDG_CACHE_HOME\""
    echo 'echo "[mdops] $(date -Is) start $MD_RUN_ID on $(hostname) job $SLURM_JOB_ID"; nvidia-smi -L 2>/dev/null'
    cat "$rd/cmd.txt"; echo
    echo 'rc=$?; echo $rc > "$MD_OUT_DIR/exit_code"; echo "[mdops] $(date -Is) exit $rc"; exit $rc'
  } > "$rd/job.sbatch"
  cp "$rd/job.sbatch" "$out/job.sbatch"
  { echo "run_id=$id"; echo "host=cluster"; echo "dir=$dir"; echo "commit=$COMMIT"; echo "dirty=$DIRTY"; echo "agent=$agent"
    echo "out_dir=$out"; echo "submitted=$(now)"; } > "$rd/meta.env"
  cp "$rd/meta.env" "$out/meta.env"; [ -f "$rd/dirty.patch" ] && cp "$rd/dirty.patch" "$out/"
  local jid; jid=$(sbatch --parsable "$rd/job.sbatch") || die "sbatch failed"
  echo "job=$jid" >> "$rd/meta.env"; echo "job=$jid" >> "$out/meta.env"
  printf '%s\t%s\tslurm\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" cluster "$name" "$COMMIT" "$DIRTY" "$agent" "$(now)" "$jid" >> "$INDEX"
  echo "RUN $id"; echo "job: $jid"; echo "out: $out"; echo "storage now: $u"
}

runs() { tail -n "${1:-20}" "$INDEX" | column -t -s $'\t' 2>/dev/null || tail -n "${1:-20}" "$INDEX"; }

run_status() { # RUN_ID
  local rd="$STATE/runs/$1"; [ -d "$rd" ] || die "unknown run $1 on $(hostname -s)"
  cat "$rd/meta.env"
  local out; out=$(sed -n 's/^out_dir=//p' "$rd/meta.env")
  for f in "$rd/exit_code" "$out/exit_code"; do [ -f "$f" ] && echo "exit_code=$(cat "$f")"; done
  local job; job=$(sed -n 's/^job=//p' "$rd/meta.env")
  [ -n "$job" ] && command -v squeue >/dev/null && squeue -j "$job" -h -o 'slurm_state=%T elapsed=%M node=%N' 2>/dev/null
  tmux has-session -t "md-$1" 2>/dev/null && echo "tmux=running"
  echo "--- log tail"; tail -n 15 "$rd/log.txt" 2>/dev/null || ls -t "$out"/slurm-*.log 2>/dev/null | head -1 | xargs -r tail -n 15
}

# ---------- prune harvested cluster run dirs (only inside WORK_ROOT/runs) ----------
prune() { # WORK_ROOT YES(0/1)
  local work=$1 yes=$2 base d real n=0
  [ -n "$work" ] && [ -d "$work/runs" ] || die "no $work/runs"
  base=$(readlink -f "$work/runs")
  for d in "$work"/runs/*/; do
    [ -f "$d/.harvested" ] || continue
    real=$(readlink -f "$d"); case "$real" in "$base"/?*) ;; *) echo "SKIP (outside $base): $d"; continue;; esac
    [ -L "${d%/}" ] && { echo "SKIP symlink: $d"; continue; }
    n=$((n+1))
    if [ "$yes" = 1 ]; then rm -rf -- "$real" && echo "deleted $real"; else echo "would delete $(du -sh "$real" | cut -f1) $real"; fi
  done
  [ $n = 0 ] && echo "nothing harvested to prune"
  [ "$yes" = 1 ] || echo "(dry run — re-run with --yes to delete)"
}


# ---------- living handoff (git-versioned on this host) ----------
HO="$STATE/handoff"
handoff_init_repo() { mkdir -p "$HO"; [ -d "$HO/.git" ] || { git -C "$HO" init -q && git -C "$HO" config user.name mdops && git -C "$HO" config user.email mdops@localhost; }; }
handoff_get() { handoff_init_repo
  if [ ! -f "$HO/HANDOFF.md" ]; then echo "@@NONE@@"; return 0; fi
  printf '@@BASE %s %s\n' "$(git -C "$HO" rev-parse --verify -q HEAD || echo none)" "$(git -C "$HO" rev-list --count HEAD 2>/dev/null || echo 0)"
  cat "$HO/HANDOFF.md"; }
handoff_put() { # AGENT BASE SUMMARY INCOMING_FILE (uploaded into $HO first)
  local agent=$1 base=$2 summary=$3 inc="$HO/${4##*/}" cur h
  handoff_init_repo; cur=$(git -C "$HO" rev-parse --verify -q HEAD || echo none)
  [ "$base" = "$cur" ] || { rm -f "$inc"; die "handoff changed since you pulled it (base $base, now $cur). Run 'mtd handoff pull', merge your changes, push again."; }
  [ -f "$inc" ] || die "no uploaded handoff file"; mv "$inc" "$HO/HANDOFF.md.new"
  [ -s "$HO/HANDOFF.md.new" ] || { rm -f "$HO/HANDOFF.md.new"; die "empty handoff refused"; }
  for h in '## Mission' '## Current state' '## Next steps' '## Session log'; do
    grep -q "^$h" "$HO/HANDOFF.md.new" || { rm -f "$HO/HANDOFF.md.new"; die "handoff refused: missing section '$h'"; }
  done
  mv "$HO/HANDOFF.md.new" "$HO/HANDOFF.md"
  git -C "$HO" add HANDOFF.md && git -C "$HO" commit -qm "$agent: $summary" || die "nothing changed"
  journal "$agent" "handoff v$(git -C "$HO" rev-list --count HEAD): $summary" >/dev/null
  echo "HANDOFF v$(git -C "$HO" rev-list --count HEAD) $(git -C "$HO" rev-parse --short HEAD)"; }
handoff_log() { handoff_init_repo; git -C "$HO" log --format='v%h %ci %s' -n "${1:-20}" 2>/dev/null || echo "(no versions)"; }

sub=${1:-}; shift || true
case "$sub" in
  lock)     a=${1:-list}; shift || true; case "$a" in acquire) lock_acquire "$@";; release) lock_release "$@";; *) lock_list;; esac ;;
  journal)  journal "$@" ;;
  journal-tail) tail -n "${1:-30}" "$STATE/journal.md" 2>/dev/null || echo "(empty journal)";;
  run-local) run_local "$@" ;;
  run-slurm) run_slurm "$@" ;;
  runs)     runs "$@" ;;
  run-status) run_status "$@" ;;
  usage)    usage "$@" ;;
  prune)    prune "$@" ;;
  mark-harvested) [ -d "$1" ] && date -u +%FT%TZ > "$1/.harvested" && echo "marked $1" ;;
  handoff-get) handoff_get ;;
  handoff-put) handoff_put "$@" ;;
  handoff-log) handoff_log "$@" ;;
  ping)     echo "pong $(hostname -s) $(now)" ;;
  *) die "unknown subcommand '$sub'" ;;
esac
