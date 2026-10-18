#!/usr/bin/env bash
# rudra-harden.sh — run ONCE on rudra with sudo (the human types the password):
#   mdops harden-rudra            (copies this file to rudra, then: ssh -t rudra sudo bash ...)
# Idempotent. Every change is a drop-in file or a systemd mask, listed at the end with its undo.
# Flags: --install-tailscale   install Tailscale from its official apt repo if missing
#        --dry-run             print what would change, change nothing
set -uo pipefail
DRY=0; INSTALL_TS=0; CHOST=; HEADLESS=0
for a in "$@"; do case "$a" in --dry-run) DRY=1;; --install-tailscale) INSTALL_TS=1;; --headless) HEADLESS=1;; --cluster-host=*) CHOST=${a#*=};; esac; done
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
U="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
UNDO=()
do_() { echo "+ $*"; [ $DRY = 1 ] || eval "$@"; }
write() { # PATH CONTENT
  if [ -f "$1" ] && [ "$(cat "$1")" = "$2" ]; then echo "= $1 unchanged"; return; fi
  echo "+ write $1"; [ $DRY = 1 ] || { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }
  UNDO+=("rm -f $1")
}

echo "== 1. never sleep/suspend (an office box that naps drops every connection)"
do_ systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
UNDO+=("systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target")
write /etc/systemd/logind.conf.d/90-mdops.conf "[Login]
HandleLidSwitch=ignore
IdleAction=ignore
KillUserProcesses=no"
do_ loginctl enable-linger "$U"   # tmux sessions + user services survive logout

echo "== 2. sshd keepalives + enough sessions for multiplexed agents"
if grep -qE '^\s*Include\s+/etc/ssh/sshd_config.d' /etc/ssh/sshd_config 2>/dev/null; then
  write /etc/ssh/sshd_config.d/90-mdops.conf "ClientAliveInterval 30
ClientAliveCountMax 6
TCPKeepAlive yes
MaxSessions 32
MaxStartups 30:30:100"
  if [ $DRY = 0 ]; then
    if sshd -t; then systemctl reload ssh 2>/dev/null || systemctl reload sshd; echo "sshd reloaded"
    else echo "!! sshd -t failed: removing drop-in"; rm -f /etc/ssh/sshd_config.d/90-mdops.conf; fi
  fi
else echo "!! sshd_config has no Include for sshd_config.d — skipped (tell the lead agent)"; fi

echo "== 3. packages agents rely on"
if command -v apt-get >/dev/null; then
  need=(); for p in tmux mosh rsync zstd pigz ncdu htop curl; do command -v "$p" >/dev/null || need+=("$p"); done
  [ ${#need[@]} -gt 0 ] && do_ "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ${need[*]}" || echo "= tools present"
  # no surprise reboots from unattended-upgrades before the deadline
  write /etc/apt/apt.conf.d/99-mdops-noreboot 'Unattended-Upgrade::Automatic-Reboot "false";'
fi

echo "== 4. Tailscale as a self-restarting service"
if ! command -v tailscale >/dev/null; then
  if [ $INSTALL_TS = 1 ]; then do_ "curl -fsSL https://tailscale.com/install.sh | sh"
  else echo "!! tailscale not installed — re-run with --install-tailscale"; fi
fi
if command -v tailscale >/dev/null; then
  do_ systemctl enable --now tailscaled
  write /etc/systemd/system/tailscaled.service.d/90-mdops.conf "[Service]
Restart=always
RestartSec=5"
  do_ systemctl daemon-reload
  if tailscale status >/dev/null 2>&1; then echo "= tailscale already logged in: $(tailscale ip -4 2>/dev/null | head -1)"
  else echo ">> run next (prints a login URL; open it on your Mac):  sudo tailscale up --hostname=rudra --accept-routes=false"; fi
fi

echo "== 5. network watchdog (checks every 2 min, restarts networking/tailscaled at most every 10 min)"
[ -f /etc/mdops/netwatch.conf ] || write /etc/mdops/netwatch.conf "# mdops netwatch settings
CLUSTER_HOST=$CHOST
# command that re-establishes rudra's ANU VPN (set once discovery shows how it runs), e.g.:
# VPN_RESTART_CMD=\"systemctl restart gpd\"
VPN_RESTART_CMD="
write /usr/local/sbin/mdops-netwatch '#!/usr/bin/env bash
S=/var/lib/mdops-netwatch; mkdir -p $S; f=$(cat $S/fails 2>/dev/null || echo 0)
CLUSTER_HOST=; VPN_RESTART_CMD=; [ -f /etc/mdops/netwatch.conf ] && . /etc/mdops/netwatch.conf
gw=$(ip route show default 2>/dev/null | awk "/default/{print \$3; exit}")
ok=0; [ -n "$gw" ] && ping -c1 -W3 "$gw" >/dev/null 2>&1 && getent hosts pypi.org >/dev/null 2>&1 && ok=1
if [ $ok = 1 ]; then echo 0 > $S/fails
  if command -v tailscale >/dev/null && ! tailscale status >/dev/null 2>&1; then
    logger -t mdops-netwatch "LAN ok but tailscale down -> restart tailscaled"; systemctl restart tailscaled; fi
  if [ -n "$CLUSTER_HOST" ] && ! timeout 8 bash -c "</dev/tcp/$CLUSTER_HOST/22" 2>/dev/null; then
    c=$(( $(cat $S/cfails 2>/dev/null || echo 0) + 1 )); echo $c > $S/cfails; logger -t mdops-netwatch "cluster $CLUSTER_HOST:22 unreachable ($c)"
    lv=$(cat $S/last_vpn 2>/dev/null || echo 0)
    if [ $c -ge 3 ] && [ -n "$VPN_RESTART_CMD" ] && [ $(( $(date +%s) - lv )) -ge 600 ]; then
      date +%s > $S/last_vpn; logger -t mdops-netwatch "restarting VPN: $VPN_RESTART_CMD"; bash -c "$VPN_RESTART_CMD"; fi
  else echo 0 > $S/cfails; fi
  exit 0; fi
f=$((f+1)); echo $f > $S/fails; logger -t mdops-netwatch "network check failed ($f in a row, gw=$gw)"
last=$(cat $S/last_restart 2>/dev/null || echo 0)
if [ $f -ge 3 ] && [ $(( $(date +%s) - last )) -ge 600 ]; then
  date +%s > $S/last_restart; logger -t mdops-netwatch "restarting network stack"
  if systemctl is-active -q NetworkManager; then systemctl restart NetworkManager; else systemctl restart systemd-networkd 2>/dev/null; fi
  sleep 20; systemctl restart tailscaled 2>/dev/null; fi'
[ $DRY = 1 ] || chmod 755 /usr/local/sbin/mdops-netwatch
write /etc/systemd/system/mdops-netwatch.service "[Unit]
Description=mdops network watchdog
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/mdops-netwatch"
write /etc/systemd/system/mdops-netwatch.timer "[Unit]
Description=mdops network watchdog every 2 min
[Timer]
OnBootSec=3min
OnUnitActiveSec=2min
[Install]
WantedBy=timers.target"
do_ systemctl daemon-reload
do_ systemctl enable --now mdops-netwatch.timer
UNDO+=("systemctl disable --now mdops-netwatch.timer")

echo "== 6. Wi-Fi power saving off (only matters if rudra is on Wi-Fi)"
[ -d /etc/NetworkManager/conf.d ] && write /etc/NetworkManager/conf.d/90-mdops-wifi-powersave.conf "[connection]
wifi.powersave = 2"

echo "== 7. GPU persistence mode (faster, steadier CUDA start-up)"
command -v nvidia-smi >/dev/null && do_ "nvidia-smi -pm 1 >/dev/null && systemctl enable --now nvidia-persistenced 2>/dev/null; true"

echo "== 8. headless (boot without the desktop: frees GPU memory and avoids display-manager sleep/lock)"
if [ $HEADLESS = 1 ]; then
  if [ "$(systemctl get-default)" != multi-user.target ]; then do_ systemctl set-default multi-user.target; UNDO+=("systemctl set-default graphical.target"); echo "   (takes effect at next reboot; nothing is stopped now)"
  else echo "= already headless"; fi
else echo "= skipped (add --headless)"; fi

echo "== 9. both uplinks (office LAN + dongle) stay managed; LAN preferred"
command -v nmcli >/dev/null && nmcli -t -f DEVICE,TYPE,STATE device | grep -vE ':(loopback|bridge|tun|wireguard)' | sed 's/^/   /'
command -v nmcli >/dev/null && for c in $(nmcli -t -f NAME,TYPE connection show | awk -F: '$2 ~ /ethernet|wireless|gsm/ {print $1}' | tr ' ' '#'); do c=${c//#/ }
  do_ "nmcli connection modify \"$c\" connection.autoconnect yes"; done

echo; echo "== done. Undo, if ever needed:"; for u in "${UNDO[@]}"; do echo "   sudo $u"; done
echo "   (then: sudo systemctl daemon-reload; sudo systemctl reload ssh)"
