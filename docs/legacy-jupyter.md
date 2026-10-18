# Legacy: Jupyter on the cluster in three commands (2023)

The original helper (`autojupyter.slurm`, the `porter` / `jrun` remote functions and the
local `jweb` tunnel) is preserved verbatim in [`index.html`](../index.html).

With mdops the same thing is: run Jupyter inside a Slurm job (never on the login node),
then `mdops tunnel cluster <port>` from the Mac — or run it on rudra with
`mdops run rudra --no-gpu ...` and `mdops tunnel rudra 8888`.
