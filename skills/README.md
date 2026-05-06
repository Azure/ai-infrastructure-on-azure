# Skills

Operational knowledge for managing Azure HPC GPU clusters on CycleCloud Workspace for Slurm and AKS. Packaged as a single `ai-infra` skill: a `SKILL.md` index that routes to detailed reference files in `references/`.

## Who Is This For?

You're on an Azure CycleCloud Workspace for Slurm cluster (or AKS), you've cloned this repo, and you've opened VS Code. You need to validate hardware, troubleshoot a slow training job, or file an Azure Guest Health Report — and you want an AI assistant (Copilot, Claude, etc.) to help.

This skill gives the assistant the domain knowledge it needs to actually help — correct commands, expected values, environment variables, and decision trees that are specific to Azure HPC GPU SKUs.

## Layout

```
skills/ai-infra/
  SKILL.md                              # YAML frontmatter + router/index + cross-cutting rules
  references/
    sku_baselines.md                    # NCCL/GPU/thermal thresholds for GB300, H100
    rack_topology.md                    # MNNVL, ClusterUUID, FabricManager
    ib_validation.md                    # IB ports, pkeys, error counters
    nccl_test.md                        # how to run all_reduce_perf (Slurm + AKS)
    nccl_diagnosis.md                   # bisection, intra/inter-rack scoping
    gpu_validation.md                   # ubergemm GEMM
    thermal_test.md                     # dcgmproftester
    outlier_detection.md                # z-score, MAD, fleet analysis
    ghr.md                              # Azure Guest Health Reporting (impact categories, REST API)
    node_drain_and_replace.md           # Slurm node lifecycle
```

The `SKILL.md` has YAML frontmatter (`name`, `description`) so assistants that support the Skills convention auto-load it for any cluster-operations question. The index inside `SKILL.md` then directs the assistant to read only the relevant `references/*.md` files for the specific question — saving context.

## How to Use

### GitHub Copilot

**Option 1 — Always-on instructions.** The repo includes `.github/copilot-instructions.md`, which Copilot auto-loads for every chat in this workspace. It points at the skill.

**Option 2 — Selective skill loading.** The repo includes a symlink at `.copilot/skills/ai-infra` pointing to `skills/ai-infra/`. Copilot reads the `description` in `SKILL.md` frontmatter and loads the skill when relevant.

**Option 3 — On demand.** Attach the skill in chat: `#file:skills/ai-infra/SKILL.md`, then attach specific references as needed.

### Claude Code

**Option 1 — Always-on instructions.** The repo includes `CLAUDE.md` at the root, which Claude auto-loads when the repo is opened. It points at the skill.

**Option 2 — On demand.** Drag `skills/ai-infra/SKILL.md` into the chat input, or reference any specific reference file directly with `@file`.

### Slash command fallback

If the assistant doesn't auto-load the skill for a relevant question, invoke it explicitly:

```
/ai-infra why is NCCL bandwidth low on rack 3?
```

This forces the assistant to load `SKILL.md` and follow its routing.

### As an agent system prompt

If you're building an AI agent, load `skills/ai-infra/SKILL.md` into the system prompt and provide tool access to read `skills/ai-infra/references/*.md` on demand. The references contain commands, thresholds, and decision logic — directly usable as context.

## Reference Index

### Concepts and baselines (orchestrator-agnostic)

| Reference                                                     | What It Covers                                                                                                               |
| ------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| [sku_baselines](ai-infra/references/sku_baselines.md)         | Expected NCCL busbw, GPU GFlops, thermal limits, IB ports, and rack sizes for GB300 and H100. Warn and GHR thresholds.       |
| [rack_topology](ai-infra/references/rack_topology.md)         | MNNVL domains, ClusterUUID discovery, expected rack sizes, FabricManager troubleshooting.                                    |
| [ib_validation](ai-infra/references/ib_validation.md)         | IB port state, partition keys, error counters, link flap detection, soft fixes.                                              |
| [nccl_diagnosis](ai-infra/references/nccl_diagnosis.md)       | Scoping intra-rack vs inter-rack failures, bisection algorithm for isolating bad nodes, GPU vs network root cause analysis.  |
| [outlier_detection](ai-infra/references/outlier_detection.md) | Statistical methods (absolute threshold, z-score, MAD) for finding degraded nodes in fleet-wide test results.                |
| [ghr](ai-infra/references/ghr.md)                             | Azure Guest Health Reporting (GHR) — complete impact category reference, IMDS/KVP data collection, REST API format, polling. |

### Test execution (Slurm; AKS counterparts referenced)

| Reference                                               | What It Covers                                                                                                                           |
| ------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| [nccl_test](ai-infra/references/nccl_test.md)           | Run NCCL all_reduce_perf via the Slurm launcher. Per-SKU env vars (MNNVL, SHARP, GDR), output columns, quick vs full sweep. AKS pointer. |
| [gpu_validation](ai-infra/references/gpu_validation.md) | Run ubergemm GEMM benchmark, parse CSV output, identify underperforming GPUs.                                                            |
| [thermal_test](ai-infra/references/thermal_test.md)     | Run dcgmproftester thermal stress, interpret pass/fail, throttle reasons, DCGMI diagnostic levels.                                       |

### Remediation

| Reference                                                               | What It Covers                                                                                                                 |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| [node_drain_and_replace](ai-infra/references/node_drain_and_replace.md) | Slurm drain/undrain commands, reboot procedure, decision tree for when to drain vs reboot vs GHR, post-replacement validation. |

## Example Workflows

### "I just got a new cluster, validate everything"

References needed: `sku_baselines`, `rack_topology`, `nccl_test`, `gpu_validation`, `thermal_test`

1. Discover rack topology (ClusterUUIDs).
2. Run NCCL all_reduce per rack (MNNVL test).
3. Run GPU GEMM test on all nodes.
4. Run thermal stress test on all nodes.
5. Compare results against SKU baselines.

### "A training job is running slow"

References needed: `nccl_diagnosis`, `sku_baselines`, `ib_validation`

1. Run a quick NCCL check on the job's nodelist.
2. If bandwidth is low, identify which rack is affected.
3. Bisect the failing rack to find the bad node.
4. Check IB links and GPU health on the suspect node.

### "I found a bad node, now what?"

References needed: `node_drain_and_replace`, `ghr`

1. Collect metadata (PhysicalHostName, Resource ID) **before** rebooting.
2. Drain the node.
3. Attempt reboot if appropriate.
4. If issue persists, file GHR with the correct impact category.
5. Poll insights for resolution status.
