# Start here

> The PI starts any agent with one line:
> **`Read ~/Desktop/MatterDoor/START_HERE.md and follow it.`**

You are joining the **MatterDoor** project partway through. It is a CVPR 2027
paper, due **16 Nov 2026 AoE**, and it completes the PI's PhD. This page takes
you from nothing to working exactly where the last session stopped. The rules
behind it are in `AGENTS.md` in this folder; read that file before your first
change.

## 0. Your role: you control the MatterDoor project
You run the project, through its control plane in
`into_the_unknown/control/`. It holds:
- `MISSION.md`: what done means;
- `registry/goals.yaml`: goals with due dates;
- `registry/jobs.yaml`: the job circuit;
- `registry/results.yaml`: the results ledger;
- `registry/decisions.yaml`: what the PI decided;
- the living handoff: where things stand.

Your job is to move those goals toward submission, in deadline order, and to
keep the control plane true as you go:
- **Every session advances a goal.** Each one ends with goals, jobs, results,
  `STATUS.md` and the handoff matching reality.
- **Watch the clock.** The briefing prints the days left and each goal's due
  date. If a goal will miss its date, tell the PI early and propose what to
  cut or reorder. Never let it slip silently.
- **Only MatterDoor is in scope.** ZeroNav is out. When something is outside
  the mission, ask the PI before spending effort on it.
- **The infrastructure (`mtd`, the portal) is finished.** Use it and don't
  redesign it. If it blocks you, run `mtd doctor` and follow
  `ANU-Cluster/docs/runbook.md`. Make a narrow fix only when you are sure;
  otherwise use `mtd ask`.
- **The PI decides; you record and execute.** Mission, goals, guards and GPU
  approvals belong to the PI. You propose them in chat and record the PI's
  words in `decisions.yaml`.

## 1. Boot (about two minutes)
```
cd ~/Desktop/MatterDoor
export MD_AGENT=<tool>-<task>      # e.g. claude-status, codex-hssd; it goes into every lock, run and commit
mtd sync                           # all repos and this manual up to date (fast-forward only)
mtd                                # the full briefing: read ALL of it before acting
```
If `mtd` is not found, run `~/MatterDoor/ANU-Cluster/bin/mtd`. If that is
missing too, ask the PI to run the bootstrap (`README.md`, "Recover").

## 2. Where the last session stopped
**The living handoff is the state of the project.** It is section 5 of the
briefing, or run `mtd handoff show`. It holds:
- the current state and mode (normal, or cluster-only when rudra is down);
- active runs and jobs, each with its next action;
- open decisions for the PI;
- next steps, in priority order.

Trust it over chat history and over your own reading of git. If the briefing
marks the handoff as a cached copy, run `mtd hub status`, then `mtd doctor`.
The research details behind it are in `into_the_unknown/control/STATUS.md` and
`control/registry/`.

## 3. Choose your work
The plan is `into_the_unknown/control/PLAN.md`. It sets out parallel lanes
(A evidence, B story and experiments, C clean code, D literature, E paper)
and how agents decide together through `control/CONSENSUS.md`.
1. If the PI gave you a task or a lane in chat, do that. For a lane, take the
   lock `lane-<X>`.
2. If no agent has done PLAN.md's **Now** steps yet (the journal and handoff
   show it), do them first. Start with `mtd cluster-wip`, which preserves the
   cluster checkout's uncommitted code.
3. Otherwise, start with **Active runs & jobs** in the handoff. Finish,
   harvest or report anything there.
4. Then take the free lane with the earliest deadline, or the first
   **Next steps** item that is not marked (PI) and not locked (`mtd lock list`).
5. Write your positions with evidence into `CONSENSUS.md`. If anything
   conflicts with `control/MISSION.md`, ask the PI.

## 4. Rules for the first five minutes (the full rules are in `AGENTS.md`)
- **Ask the PI before anything is deleted or uploaded.** That includes
  `git push`, staging data and sending files. After a yes, pass
  `--approved "<their words + time>"`.
- **An approval covers one execution.** Jobs marked `once: true` run a single
  time, and the portal refuses a second run.
- **Never disrupt another agent:** its runs, locks, tmux sessions or
  uncommitted files, including on the cluster.
- **Cluster login node: job control only.** GPU work goes through
  `mtd submit … --job job:<id>`, and only for jobs approved in `jobs.yaml`.
  CPU work goes through `mtd run cluster --no-gpu …`.
- **Never type, store or ask for passwords.** If a host needs one, the PI
  runs `mtd login <host>`.
- **No invented numbers or citations.** Every number needs a `results.yaml`
  row with a run id and commit.
- **ZeroNav material is out of scope.**
- **If you cannot access something, do not work around it.** Run
  `mtd ask "<what> — <why>"`, tell the PI, and do other work.
- **Use the levers.** They print one line each and check their own effect:
  `mtd check | sync | save | backup | status | submit | harvest | handoff | cluster-wip`.
  `mtd sync` and `mtd backup` push code and docs for you.

## 5. If you cannot reach the machines
If `mtd doctor` shows every host unreachable and you have no SSH keys, you are
running in a sandbox. Work only on the files in this folder. Record any
remote step in the handoff's next steps or with `mtd ask`, so that a local
session can run it.

## 6. End of session (mandatory, so the next agent starts where you stop)
1. Leave every run you started running (and journaled), finished and
   harvested, or cancelled.
2. Commit your work with `mtd save <repo> "msg"`. Update `STATUS.md` and the
   registry if anything changed, then run `mtd check`.
3. Update the handoff:
   - `mtd handoff pull`;
   - edit `ANU-Cluster/state/handoff/HANDOFF.md` in place: current state,
     active runs, decisions, problems and next steps in order;
   - `mtd handoff push "one-line summary"`.
4. Run `mtd backup`, then release your locks.
