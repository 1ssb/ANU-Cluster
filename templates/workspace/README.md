# MatterDoor workspace (for the PI)

This folder is the whole project in one place. Point any agent (Claude, Codex,
Copilot, …) at **`~/Desktop/MatterDoor`**. It reads `AGENTS.md`, runs `mtd`,
and knows everything else from there.

## Start an agent
- **Claude desktop / Cowork:** add the folder `~/Desktop/MatterDoor` to the
  chat, then say what you want. The agent's first command is `mtd`.
- **From Terminal:** `mtd agent claude "task"` or `mtd agent codex "task"`.
  This starts that CLI here, already briefed.
- **Any other agent:** tell it "Read `~/Desktop/MatterDoor/AGENTS.md` and
  follow it."

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

## Never lost
- **Code, documents and environment snapshots** are committed and mirrored to
  rudra (including uncommitted work, as snapshot refs) by `mtd backup`. That
  runs every 2 h and at the end of each agent session. With your standing
  approval it also pushes to GitHub.
- **Data is never uploaded.** It is described, with locations and checksums,
  in `into_the_unknown/control/registry/resources.yaml`.
- **The handoff** is versioned on rudra and mirrored into the project repo.

## Recover
- **Something is broken:** run `mtd doctor`, then see
  `ANU-Cluster/docs/runbook.md`.
- **Rebuild this workspace on a new Mac:**
  `git clone https://github.com/1ssb/ANU-Cluster ~/MatterDoor/ANU-Cluster && ~/MatterDoor/ANU-Cluster/bootstrap.sh`
