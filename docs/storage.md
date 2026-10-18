# Storage plan

Principle: one canonical copy, a disposable cluster working set, and verified
moves between them. Nothing irreplaceable lives only on the cluster work root.

| tier | where | contents | lifecycle |
|---|---|---|---|
| code | GitHub (project repos) | all code, configs, job scripts, paper | commit → push → `git pull` on the host |
| canonical data | `RUDRA_DATA_ROOT` on rudra | raw datasets, model weights, harvested runs (`runs/<id>`) | written once; read-only after ingest |
| archive | `RUDRA_ARCHIVE_ROOT` on rudra | cold material as `.tar.zst` + `.sha256` + `.list.txt` | `mdops archive`; originals removed only after verification |
| cluster work | `CLUSTER_WORK_ROOT` | `stage/` (inputs for jobs), `runs/` (job outputs), `cache/`, `tmp/` | staged → used → harvested → pruned |
| cluster group | `CLUSTER_GROUP_ROOT` (`/home/group/rudra-work`) | existing project assets (models, frozen releases) | read-mostly; mdops never prunes it |
| cluster node scratch | `/raid/$USER/...` on compute nodes | per-job temp | job-scoped, per the project contract |
| Mac | the paper repo + small results | figures, tables, LaTeX | git |

## Limits and modes
- **Cluster writes.** Cluster writes refuse when the work root has less than
  `CLUSTER_MIN_FREE_GB` free (default 40) or is above `CLUSTER_QUOTA_STOP_PCT`
  used (default 99). The percentage alone is meaningless on a shared 4.5 TB
  volume that is already at 99%.
- **Without rudra.** The canonical copy of small results is this Mac
  (`~/MatterDoor/data/runs/<id>`, never in git). Large data stays in the
  cluster group storage, recorded in the project registry.

## How the numbers get filled in
1. `mdops discover` maps every symlink in `matterdoor` / `rudra-work` / `rudra-shared` and the rudra disks. On the cluster it uses only depth-1 listings, never scans.
2. `mdops census` measures cluster sizes inside a Slurm CPU job.
3. The lead agent sets `RUDRA_DATA_ROOT`, `RUDRA_ARCHIVE_ROOT` and `CLUSTER_WORK_ROOT` in `config/hosts.conf`, records the decision with `mdops journal`, and runs `mdops doctor`.
4. Symlink tangles are resolved by documenting each link's target in the project repo (`ops/storage-map.md`). Shared links under `/home/group` are not rewritten; other lab members may depend on them.

## Rudra cleanup order
1. `mdops clean scan` lists the largest directories, caches and large files.
2. `mdops clean caches --yes` clears caches: pip, conda packages, trash and thumbnails. HuggingFace models older than 30 days are only listed, never deleted.
3. `mdops archive PATH --yes` compresses and verifies; `--remove-original` deletes the original only after the count check passes.
4. Anything not a cache is shown to the human before an original is removed.
