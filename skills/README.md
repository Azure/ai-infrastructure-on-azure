# Skills

Operational knowledge for managing Azure HPC GPU clusters. Each skill is a self-contained markdown document covering one aspect of cluster validation, diagnosis, or remediation.

## Who Is This For?

You're on an Azure CycleCloud Workspace for Slurm cluster, you've cloned this repo, and you've opened VS Code. You need to validate hardware, troubleshoot a slow training job, or file an Azure health report — and you want an AI assistant (Copilot, Claude, etc.) to help.

These skills give the assistant the domain knowledge it needs to actually help — correct commands, expected values, environment variables, and decision trees that are specific to Azure HPC GPU SKUs.

## How to Use

Each skill is a directory containing a `SKILL.md` file with YAML frontmatter (`name`, `description`) and the full skill content. This structure is directly compatible with `.copilot/skills/` and easy to reference from any assistant.

```
skills/slurm/
  nccl_allreduce_test/
    SKILL.md              # frontmatter + full skill content
  rack_topology/
    SKILL.md
  ...
```

### GitHub Copilot

**Option 1 — Always-on instructions.** The repo includes `.github/copilot-instructions.md`, which Copilot auto-loads for every chat in this workspace. It points to these skills.

**Option 2 — Selective skill loading.** Copy (or symlink) skill directories into `.copilot/skills/` at the repo root:

```bash
# Copy all skills
cp -r skills/slurm/* .copilot/skills/

# Or symlink individual ones
mkdir -p .copilot/skills
ln -s ../../skills/slurm/nccl_performance_diagnosis .copilot/skills/
```

Copilot reads the `description` in each `SKILL.md` frontmatter and **selectively loads only relevant skills** based on the query — better than always-on when you have many skills.

**Option 3 — On demand.** Attach a specific skill in chat: `#file:skills/slurm/nccl_performance_diagnosis/SKILL.md`

### Claude Code

**Option 1 — Always-on instructions.** The repo includes `CLAUDE.md` at the root, which Claude auto-loads when the repo is opened. It points to these skills.

**Option 2 — Subdirectory CLAUDE.md.** Claude Code also reads `CLAUDE.md` files in subdirectories for scoped context. You could add a `skills/slurm/CLAUDE.md` that lists all skills in that directory.

**Option 3 — On demand.** Drag a skill file into the chat input or reference it with `@file`.

### As agent system prompts

If you're building an AI agent, load the relevant `SKILL.md` content into the system prompt. The skills are written to be directly usable as context — they contain commands, thresholds, and decision logic, not just descriptions.

## Skills Reference

### Routing — Choose the right skill set first

| Skill | What It Covers |
|-------|---------------|
| [slurm_router](slurm/slurm_router/SKILL.md) | Intent-to-skill routing for Slurm operations. Selects the correct skills first, then enforces exact commands, thresholds, and action decisions from those skills. |

### Diagnostic — How to run tests and read results

| Skill | What It Covers |
|-------|---------------|
| [sku_performance_baseline](slurm/sku_performance_baseline/SKILL.md) | Expected NCCL busbw, GPU GFlops, thermal limits, IB ports, and rack sizes for GB300 and H100 SKUs. Warn and GHR thresholds. |
| [node_gpu_validation](slurm/node_gpu_validation/SKILL.md) | Running ubergemm GEMM benchmarks, parsing CSV output, identifying underperforming GPUs, fleet-wide analysis. |
| [ib_link_validation](slurm/ib_link_validation/SKILL.md) | Checking IB port state (operstate, ibstat), partition keys, error counters, link flap detection, and soft fixes. |
| [nccl_allreduce_test](slurm/nccl_allreduce_test/SKILL.md) | Running NCCL all_reduce_perf via the launcher, per-SKU environment variables (MNNVL, SHARP, GDR), output columns, quick vs full sweep. |
| [thermal_stress_test](slurm/thermal_stress_test/SKILL.md) | Running dcgmproftester thermal stress, interpreting pass/fail, supplementary diagnostics (temperatures, throttle reasons, DCGMI levels). |

### Reasoning — How to analyze and isolate problems

| Skill | What It Covers |
|-------|---------------|
| [nccl_performance_diagnosis](slurm/nccl_performance_diagnosis/SKILL.md) | Scoping intra-rack vs inter-rack failures, bisection algorithm for isolating bad nodes, GPU vs network root cause analysis. |
| [cluster_outlier_detection](slurm/cluster_outlier_detection/SKILL.md) | Statistical methods (absolute threshold, z-score, MAD) for finding degraded nodes in fleet-wide test results. |
| [rack_topology](slurm/rack_topology/SKILL.md) | MNNVL domains, ClusterUUID discovery via nvidia-smi, expected rack sizes, FabricManager troubleshooting. |

### Remediation — How to fix or replace bad hardware

| Skill | What It Covers |
|-------|---------------|
| [azure_node_health_report](slurm/azure_node_health_report/SKILL.md) | Complete GHR impact category reference (26 categories), collecting PhysicalHostName and Resource ID, REST API format, polling insights. |
| [node_drain_and_replace](slurm/node_drain_and_replace/SKILL.md) | Slurm drain/undrain commands, reboot procedure, decision tree for when to drain vs reboot vs GHR, post-replacement validation. |

## Example Workflows

### "I just got a new cluster, validate everything"

Skills needed: `slurm_router`, `sku_performance_baseline`, `rack_topology`, `nccl_allreduce_test`, `node_gpu_validation`, `thermal_stress_test`

1. Discover rack topology (ClusterUUIDs).
2. Run NCCL all_reduce per rack (MNNVL test).
3. Run GPU GEMM test on all nodes.
4. Run thermal stress test on all nodes.
5. Compare results against SKU baselines.

### "A training job is running slow"

Skills needed: `slurm_router`, `nccl_performance_diagnosis`, `sku_performance_baseline`, `ib_link_validation`

1. Run a quick NCCL check on the job's nodelist.
2. If bandwidth is low, identify which rack is affected.
3. Bisect the failing rack to find the bad node.
4. Check IB links and GPU health on the suspect node.

### "I found a bad node, now what?"

Skills needed: `slurm_router`, `node_drain_and_replace`, `azure_node_health_report`

1. Collect metadata (PhysicalHostName, Resource ID) **before** rebooting.
2. Drain the node.
3. Attempt reboot if appropriate.
4. If issue persists, file GHR with the correct impact category.
5. Poll insights for resolution status.
