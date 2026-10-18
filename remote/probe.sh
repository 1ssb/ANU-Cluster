#!/usr/bin/env bash
# mdops probe — READ-ONLY inventory of rudra or the cluster login node.
# Streamed over ssh by `mdops discover`; writes nothing, deletes nothing.
#
# Cluster role obeys the login-node contract (into_the_unknown/AGENTS.md):
#   no du / recursive find / grep / checksum over /home/group, homes or models;
#   only df, quota, Slurm queries, and depth-1 `ls` / `readlink` of NAMED dirs.
#   Sizes on the cluster come from `mdops census` (a Slurm CPU job), never from here.
# Rudra role (your own box) may scan sizes, with timeouts.
#
# Env in: MD_ROLE (rudra|cluster), MD_PEER_HOST, MD_PEER_USER, MD_NAMED_DIRS (colon list)
set -u
ROLE="${MD_ROLE:-unknown}"
T() { local s=$1; shift; if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"; else "$@"; fi; }
export -f T
H() { printf '\n===== %s =====\n' "$*"; }
run() { printf '$ %s\n' "$*"; T "${TMAX:-20}" bash -c "$*" 2>&1 | head -n "${LINES_MAX:-80}"; }

H "identity ($ROLE)"
run 'hostname; hostname -f 2>/dev/null; whoami; id; echo SLURM_JOB_ID=${SLURM_JOB_ID:-none}'
run 'uname -r; grep -E "^PRETTY_NAME=" /etc/os-release; uptime; nproc; free -h | head -2'
run 'echo HOME=$HOME SHELL=$SHELL; env | grep -iE "^(scratch|tmpdir|work|group|project)[a-z_]*=" | sort'

H "filesystems + quotas (df/quota only)"
run 'df -hT -x tmpfs -x devtmpfs -x overlay -x squashfs 2>/dev/null | head -30'
run 'quota -s 2>&1 | head -20'
run 'for m in $(df -t lustre --output=target 2>/dev/null | tail -n +2); do echo "-- lustre $m"; lfs quota -h -u "$USER" "$m"; lfs quota -h -g "$(id -gn)" "$m"; done'

if [ "$ROLE" = cluster ]; then
  H "group dirs (depth 1 only — no recursion on the login node)"
  PAT="${MD_PATTERNS:-matterdoor rudra}"
  CAND="/home/group"; for p in $PAT; do for d in /home/group/*"$p"* /home/group/*/*"$p"*; do [ -d "$d" ] && CAND="$CAND:$d"; done; done
  CAND="$CAND:${MD_NAMED_DIRS:-}"
  printf '%s\n' "${CAND//:/$'\n'}" | awk 'NF && !seen[$0]++' | head -25 | while IFS= read -r d; do
    [ -d "$d" ] || continue
    printf -- '\n-- %s  (realpath %s)\n' "$d" "$(readlink -f "$d")"
    T 10 ls -la --time-style=long-iso "$d" 2>&1 | head -70
    T 10 find "$d" -mindepth 1 -maxdepth 1 -type l -printf '%p -> %l\n' 2>/dev/null | while IFS= read -r line; do
      l=${line%% -> *}; [ -e "$l" ] && st=ok || st=BROKEN; printf 'LINK %s [%s] resolved=%s\n' "$line" "$st" "$(readlink -f "$l" 2>/dev/null)"
    done
  done
  H "project checkouts (cheap git metadata only)"
  for g in /home/group/*/projects/*/.git ${MD_PROJECT_ROOT:+$MD_PROJECT_ROOT/.git}; do
    [ -e "$g" ] || continue; P=$(dirname "$g")
    printf '[%s] origin=%s branch=%s head=%s\n' "$P" "$(git -C "$P" remote get-url origin 2>/dev/null)" "$(git -C "$P" rev-parse --abbrev-ref HEAD 2>/dev/null)" "$(git -C "$P" log -1 --format='%h %cs %s' 2>/dev/null | cut -c1-90)"
  done 2>/dev/null | head -15
  run "ls -la ~ | head -40"
  run 'ls -ld /raid/$USER 2>/dev/null; echo "(raid is per-node scratch on compute nodes)"'
else
  H "home top-level sizes (timeout 150s)"
  TMAX=160 LINES_MAX=60 run 'cd ~ && T 150 du -xsh -- * .[!.]* 2>/dev/null | sort -h | tail -45'
  H "matterdoor / into_the_unknown / rudra-work roots on $ROLE"
  ROOTS=$( { find ~ -maxdepth 3 \( -iname '*matterdoor*' -o -iname '*rudra*' -o -iname '*into_the_unknown*' \) 2>/dev/null
             for g in /data /mnt /media /scratch /srv; do [ -d "$g" ] && T 30 find "$g" -maxdepth 3 \( -iname '*matterdoor*' -o -iname '*rudra*' -o -iname '*unknown*' \) 2>/dev/null; done; } \
           | grep -vE '/(\.git|node_modules|site-packages)/' | sort -u | head -30 )
  printf '%s\n' "$ROOTS"
  printf '%s\n' "$ROOTS" | while IFS= read -r R; do
    [ -e "$R" ] || continue
    H "map: $R"
    printf -- '-- realpath: %s\n' "$(readlink -f "$R" 2>/dev/null)"
    [ -d "$R" ] || continue
    T 10 ls -la --time-style=long-iso "$R" | head -50
    printf -- '-- symlinks (depth<=4): link -> target | state | size\n'
    T 60 find "$R" -maxdepth 4 -type l 2>/dev/null | head -60 | while IFS= read -r L; do
      if [ -e "$L" ]; then st=ok; sz=$(T 30 du -sh "$(readlink -f "$L")" 2>/dev/null | cut -f1); else st=BROKEN; sz=-; fi
      printf '%s -> %s | %s | %s\n' "$L" "$(readlink "$L")" "$st" "${sz:-?}"
    done
    printf -- '-- child sizes\n'; T 120 du -sh "$R"/* "$R"/.[!.]* 2>/dev/null | sort -h | tail -30
    printf -- '-- git repos\n'
    T 30 find "$R" -maxdepth 3 -name .git -prune 2>/dev/null | head -15 | while IFS= read -r G; do d=$(dirname "$G")
      printf '[%s] origin=%s branch=%s head=%s dirty=%s last=%s\n' "$d" "$(git -C "$d" remote get-url origin 2>/dev/null || echo none)" \
        "$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null)" "$(git -C "$d" rev-parse --short HEAD 2>/dev/null)" \
        "$(T 20 git -C "$d" status --porcelain 2>/dev/null | wc -l)" "$(git -C "$d" log -1 --format=%cs 2>/dev/null)"
    done
  done
  H "reclaimable caches"
  for c in ~/.cache/pip ~/.cache/huggingface ~/.cache/torch ~/.cache/wandb ~/.cache/conda ~/.conda/pkgs ~/miniconda3/pkgs \
           ~/anaconda3/pkgs ~/miniforge3/pkgs ~/.local/share/Trash ~/.nv ~/.triton ~/.cache/thumbnails ~/.npm ~/wandb ~/.ollama; do
    [ -e "$c" ] && printf '%s\t%s\n' "$(T 60 du -sh "$c" 2>/dev/null | cut -f1)" "$c"
  done
  run 'command -v docker >/dev/null && T 20 docker system df 2>&1 | head -12'
  run 'ls -d ~/miniconda3/envs/* ~/anaconda3/envs/* ~/.conda/envs/* ~/miniforge3/envs/* 2>/dev/null | head -30'
  H "largest files on the home filesystem (>2G)"
  T 240 find ~ -xdev -type f -size +2G -printf '%s\t%TY-%Tm-%Td\t%p\n' 2>/dev/null | sort -nr | head -40 \
    | awk -F'\t' '{printf "%7.1fG\t%s\t%s\n", $1/1073741824, $2, $3}'
  H "gpu"
  run 'nvidia-smi --query-gpu=name,memory.total,memory.used,utilization.gpu,driver_version,persistence_mode --format=csv'
  run 'nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv | head'
fi

H "slurm (queries only)"
run 'command -v sinfo >/dev/null || echo "no slurm here"'
run 'sinfo -o "%P %a %l %D %G" 2>/dev/null | head -25'
run 'squeue -u "$USER" -o "%i %j %T %M %R" 2>/dev/null | head -25'
run 'sacctmgr -nP show assoc user="$USER" format=account,partition,qos 2>/dev/null | head -10'

H "network + VPN"
run 'ip -brief addr 2>/dev/null; ip route 2>/dev/null | head -6'
run 'command -v nmcli >/dev/null && nmcli -t general status && nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device'
run 'systemctl is-active NetworkManager systemd-networkd tailscaled ssh sshd 2>/dev/null | paste -sd" "'
run 'command -v tailscale >/dev/null && tailscale status 2>&1 | head -15 || echo "tailscale cli not found"'
run 'pgrep -a -f "gpd|PanGP|globalprotect|openconnect|gpclient|vpnc|openvpn|wg-quick" 2>/dev/null | grep -v pgrep | cut -c1-160'
run 'systemctl list-units --all --no-legend 2>/dev/null | grep -iE "gpd|globalprotect|openconnect|vpn|wg-quick|tailscale" | cut -c1-120'
run 'ip -brief link 2>/dev/null | grep -E "^(tun|gpd|wg|ppp|tailscale)"; ip route 2>/dev/null | grep -E "dev (tun|gpd|wg|ppp)" | head'
run 'command -v globalprotect >/dev/null && globalprotect show --status 2>&1 | head -10'
if [ "$ROLE" = rudra ]; then
  run 'T 8 curl -sS -o /dev/null -w "pypi %{http_code} %{time_total}s\n" https://pypi.org/simple/'
  run 'last -x reboot shutdown 2>/dev/null | head -10'
  run 'journalctl --since "-7 days" -u NetworkManager 2>/dev/null | grep -ciE "disconnect|deactivat|link (is )?down"; echo "(NM disconnect-ish events, last 7 days)"'
  run 'grep -hiE "^\s*(ClientAlive|TCPKeepAlive|MaxSessions|PasswordAuthentication)" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null'
  run 'systemctl is-enabled sleep.target suspend.target 2>&1 | paste -sd" "; loginctl show-user "$USER" -p Linger 2>/dev/null'
  run 'sudo -n true 2>/dev/null && echo "passwordless sudo: yes" || echo "passwordless sudo: no"'
  run 'crontab -l 2>/dev/null | grep -v "^#" | head'
fi
if [ -n "${MD_PEER_HOST:-}" ]; then
  H "reach $MD_PEER_HOST from here"
  run "T 8 bash -c '</dev/tcp/$MD_PEER_HOST/22' && echo 'tcp/22 open' || echo 'tcp/22 CLOSED'"
  run "ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new ${MD_PEER_USER:+$MD_PEER_USER@}$MD_PEER_HOST true && echo 'key auth to peer: OK' || echo 'key auth to peer: not set up'"
  run 'grep -iE "^\s*host " ~/.ssh/config 2>/dev/null | head -20'
fi
H "tools"
run 'for t in tmux mosh rsync git git-lfs zstd pigz ncdu python3 conda mamba uv apptainer docker; do printf "%-9s %s\n" "$t" "$(command -v $t || echo -)"; done'
echo; echo "probe done $(date -Is)"
