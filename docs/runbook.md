# Runbook: symptom → what to do

Start with `mdops doctor`. It names the failing layer.

| symptom | likely cause | do this |
|---|---|---|
| Tailscale not running on this Mac | app quit, or logged out | `mdops net up`; if logged out, a human signs in from the menu bar app |
| rudra unreachable via `md-rudra`, OK via `md-rudra-lan` | rudra's tailscaled down, or a key expired | wait 2 min (the watchdog restarts tailscaled); then on rudra run `sudo systemctl restart tailscaled`; in the admin console, check key expiry |
| rudra unreachable on every route | rudra off, asleep, or its network is down | the watchdog restarts networking every 10 min at most. If still down after 15 min, someone at the office power-cycles it (AnyDesk if available). Never loop retries. |
| cluster unreachable via rudra, rudra OK | rudra's VPN/LAN path to the cluster is down, or the cluster is in maintenance | try `mdops route cluster` (it tries direct routes). Check ANU status pages and maintenance notices. If rudra's VPN needs MFA, a human signs in. |
| `doctor` says a host "needs a human login" | password or OTP auth with no key | human runs `mdops login cluster` once; every agent reuses that connection for 4h |
| `login-node guard: X is not allowed` | an agent tried compute or downloads on the login node | GPU: `mdops submit cluster/JOB.sh`. CPU: `mdops run cluster --no-gpu ...`. Downloads: on rudra, then `mdops stage`. |
| `stage`/`run` refused: storage at N% | cluster work root near quota | `mdops runs cluster` → `mdops harvest ID --yes` → `mdops prune --yes`; `mdops census` to see what is big |
| `lock X is BUSY` | another agent holds it | `mdops journal --tail 20` to see who and why. Wait for the TTL; never `--force` without the human. |
| rsync stalls | flaky link | already handled: `--timeout=120`, 5 resumable attempts with `--partial`. If all five fail, re-run the same command; it resumes. |
| run refused: uncommitted changes | reproducibility gate | commit and push first. `--allow-dirty` only for throwaway debugging (the diff is saved). |
| ssh says host key changed for md-rudra / md-cluster | rudra reinstalled, or a route now hits a different machine | stop. Verify with the human before removing the old key (`ssh-keygen -R md-rudra`). |

## Recovering a broken state
- **Stale connections.** Remove `~/.ssh/cm/*` and `state/route.*`, then run
  `mdops doctor`.
- **ssh config.** Run `mdops sshconfig`; it regenerates the file from
  `config/hosts.conf`.
- **Undo the portal on the Mac.**
  1. Run `mdops keepalive uninstall`.
  2. Delete the two mdops lines at the top of `~/.ssh/config`.
  3. Remove `~/.ssh/config.d/matterdoor.conf` and `~/bin/mdops`.
- **Undo the rudra hardening.** `mdops harden-rudra` printed undo commands
  when it ran; they are also re-printed by `--dry-run`.
