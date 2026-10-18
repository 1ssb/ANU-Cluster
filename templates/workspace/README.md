# MatterDoor workspace (for the PI)

This folder is the whole project in one place. Point any agent (Claude, Codex,
Copilot, …) at **`~/Desktop/MatterDoor`**. It reads `AGENTS.md`, runs `mtd`,
and knows everything else from there.

## Start an agent
- **Best: a local session.** In the Claude desktop app, open the **Code**
  tab and choose the folder `~/Desktop/MatterDoor`.
  - It runs on this Mac with your SSH keys and network, so it can reach rudra
    and the cluster.
  - It can run `mtd doctor` and `mtd setup` and fix problems itself.
  - If a password is ever needed, it asks you to run `mtd login rudra` or
    `mtd login cluster` in Terminal, and you type the password there.
- **Terminal:** `mtd agent claude "task"`, if the Claude Code command-line
  tool is installed (see code.claude.com).
- **Sandboxed chats (e.g. Cowork) and any other agent:** tell it "Read
  `~/Desktop/MatterDoor/AGENTS.md` and follow it." Sandboxed chats cannot
  reach rudra or the cluster, so they work on files here and hand remote steps
  to a local session.

`AGENTS.md`, `CLAUDE.md` and this README are copies of the portal's
`templates/workspace/`. `mtd sync` refreshes them; it backs up a local edit
to `scratch/manual-backups/`. Make lasting changes in the portal.

## What is where
| folder | GitHub | what |
|---|---|---|
| `ANU-Cluster/` | 1ssb/ANU-Cluster (public) | the portal: `mtd` / `mdops` |
| `into_the_unknown/` | 1ssb/into_the_unknown (private) | MatterDoor code + `control/` (mission, status, knowledge graph, rules) |
| `into_the_unknown_paper/` | 1ssb/into_the_unknown_paper (private) | manuscripts and reviews |
| `data/` | not versioned | pointers to data on rudra / the cluster |
| `scratch/` | not versioned | temporary files |

## Your levers
| you want | run |
|---|---|
| everything at a glance | `mtd status` (resources in use), `mtd` (full briefing) |
| what agents need from you | `mtd ask --list`; close one with `mtd ask --close N "answer"` |
| approve something an agent asked for | reply in chat; the agent repeats the command with `--approved "<your words>"` |
| approve a GPU job | set its `status: approved` in `into_the_unknown/control/registry/jobs.yaml` |
| allow or stop automatic backups to GitHub + rudra | set `BACKUP_STANDING_APPROVAL=yes` / `no` in `ANU-Cluster/config/hosts.conf` |
| a login that needs your password or OTP | `mtd login rudra` or `mtd login cluster` |
| one-time rudra hardening (sudo) | `mtd harden-rudra` |
| health | `mtd doctor` |
| rudra is off or unreachable for a while | `mtd hub use cluster` (everything continues on the cluster; back with `mtd hub use rudra`) |

## Never lost
- **Code, documents and environment snapshots** are committed and mirrored to
  rudra (including uncommitted work, as snapshot refs) by `mtd backup`. That
  runs every 2 h and at the end of each agent session. With your standing
  approval it also pushes to GitHub.
- **Data is never uploaded.** It is described, with locations and checksums,
  in `into_the_unknown/control/registry/resources.yaml`.
- **The handoff** is versioned on the hub (rudra, or the cluster without
  rudra) and mirrored into the project repo.
- **Without rudra** backups go to GitHub only, and results are harvested to
  `data/runs/` on this Mac.

## Recover
- **Something is broken:** run `mtd doctor`, then see
  `ANU-Cluster/docs/runbook.md`.
- **Rebuild this workspace on a new Mac:**
  `git clone https://github.com/1ssb/ANU-Cluster ~/MatterDoor/ANU-Cluster && ~/MatterDoor/ANU-Cluster/bootstrap.sh`
