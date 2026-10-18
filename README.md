# ANU-Cluster

Tools for working on the ANU CECS Slurm cluster from a laptop, through an
always-on office GPU box.

## mtd / mdops: the access portal
Every agent session starts with **`mtd`**. It prints one briefing: the
rules, live state of every machine, running work, the agents' journal, and
the **living handoff**. The handoff is a single document that each session
updates at the end with `mtd handoff pull/push`, with every version kept.
`mtd X` is the same as `mdops X`.

`mdops` is one command, for humans and AI agents, that gives you:

- **Robust routes.**
  - Laptop → Tailscale → office box → cluster, with campus/VPN fallbacks.
  - Connections are multiplexed and kept alive.
  - The keepalive is a macOS LaunchAgent that reopens a dropped connection
    within 60 seconds.
- **A login-node guard.** Agents can run only queue and inspection commands
  on the login node. GPU jobs go through the project's own submit guard.
- **Safe data movement.** Stage, harvest and prune are dry-run by default,
  resumable, quota-checked and verified.
- **Reproducible runs.** A git-clean gate, run records with commit and diff,
  and a GPU queue on the office box.
- **Coordination between agents.** Atomic locks with TTL, and a shared journal.
- **Office-box hardening.** No sleep, sshd keepalives, Tailscale that restarts
  itself, and a network watchdog.

Install on the Mac:
```bash
git clone https://github.com/1ssb/ANU-Cluster.git ~/ANU-Cluster && ~/ANU-Cluster/install.sh
mtd     # the briefing
```
`install.sh` adds one `Include` line to `~/.ssh/config`, links `~/bin/mdops`,
runs a read-only discovery scan of all three machines, and writes
machine-specific settings to `config/hosts.conf`. That file is gitignored and
never committed.

- Agents: read [AGENTS.md](AGENTS.md).
- Networking: [docs/network.md](docs/network.md).
- Failures: [docs/runbook.md](docs/runbook.md).
- Storage: [docs/storage.md](docs/storage.md).

## Older tools
[docs/legacy-jupyter.md](docs/legacy-jupyter.md) covers the 2023 three-command
Jupyter-on-cluster helper (`autojupyter.slurm`, `porter`, `jweb`).
