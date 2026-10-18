# Network: Tailscale, the ANU VPN, and rudra as the jump host

```
Mac ──Tailscale (works anywhere)──► rudra ──campus LAN / rudra's ANU VPN──► cluster1 (login) ──Slurm──► GPU nodes
 │                                      ▲
 └──fallback: campus or GlobalProtect───┘   (md-rudra-lan, md-cluster-direct)
```

## Why rudra is the hub
- **Always on, on campus.** Rudra sits on the network that reaches the cluster.
  Through rudra, the Mac reaches the cluster without the ANU VPN running on the
  Mac.
- **Tailscale reaches rudra from anywhere.** Tailscale punches through NAT, and
  falls back to its DERP relays when it can't. No campus ports are opened, and
  rudra advertises no subnet routes.
- **One login, reused everywhere.** SSH connections are multiplexed: one login
  per host is reused by every agent for up to 4 hours. A keepalive agent on
  the Mac reopens a dropped connection within 60 seconds.

## One-time steps (a human does these; about 10 minutes)
1. **Rudra on Tailscale.** Skip if `mdops doctor` already says "rudra listed
   on the tailnet". Otherwise:
   - Run `mdops harden-rudra --install-tailscale`; you type the sudo password.
   - Then, on rudra, run `sudo tailscale up --hostname=rudra --accept-routes=false`.
   - Open the printed URL on your Mac and approve.
   - In the Tailscale admin console, disable key expiry for rudra.
   - Back on the Mac, run `mdops discover --regen` so the Tailscale IP becomes
     the primary route.
2. **Harden rudra.** Run `mdops harden-rudra` (sudo, idempotent; undo steps are
   printed at the end). It:
   - masks sleep and suspend;
   - adds sshd keepalives;
   - installs tmux, mosh, rsync, zstd and pigz;
   - turns off unattended-upgrade reboots;
   - makes Tailscale restart itself;
   - installs a network watchdog (every 2 min);
   - turns on GPU persistence mode.
3. **Rudra → cluster key.** Run `mdops link-rudra-cluster --yes`. This lets
   data move rudra↔cluster directly, without passing through the Mac.
4. **Keepalive on the Mac.** Run `mdops keepalive install`; `install.sh` does
   this for you.

## The ANU VPN (GlobalProtect)
- **Where it runs.** Wherever the ANU VPN runs (the Mac or rudra), it carries
  only campus-bound traffic. Tailscale uses its own interface and the
  100.64.0.0/10 range, so the two coexist.
- **If a full-tunnel VPN on the Mac breaks Tailscale.** `mdops doctor` shows
  rudra on a fallback route. Disconnect the VPN on the Mac; the rudra jump
  doesn't need it.
- **If rudra's own VPN drops.** The watchdog notices the cluster stopped
  answering. Then:
  - It restarts the VPN, at most every 10 minutes, if
    `/etc/mdops/netwatch.conf` sets `VPN_RESTART_CMD`. This is set after
    discovery shows how rudra runs the VPN.
  - If the VPN needs MFA to reconnect, the watchdog can't do it. `doctor`
    will show the cluster unreachable via rudra, and a human signs in again.
- **Manual control.**
  - `mdops net status`: Tailscale and GlobalProtect state.
  - `mdops net up`: bring Tailscale up.
  - `mdops net vpn`: opens the GlobalProtect app for a human sign-in.
  - `mdops net down --yes`: human only.

## Interactive use
- `mdops open rudra` uses mosh + tmux when mosh is installed on both ends.
  The session survives sleep, Wi-Fi changes and IP changes.
- `mdops open cluster` gives an ssh + tmux shell on the login node. It is for
  editing and inspection only.
- `mdops tunnel rudra 8888` forwards Jupyter or TensorBoard over the live
  connection.
- VS Code Remote-SSH works with the hosts `md-rudra` and `md-cluster`.
