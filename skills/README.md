# Skills

Operational knowledge for managing Azure HPC GPU clusters. Each skill is a self-contained markdown document covering one aspect of cluster validation, diagnosis, or remediation.

## Who Is This For?

You're on an Azure CycleCloud Workspace for Slurm cluster, you've cloned this repo, and you've opened VS Code. You need to validate hardware, troubleshoot a slow training job, or file an Azure health report — and you want an AI assistant (Copilot, Claude, etc.) to help.

These skills give the assistant the domain knowledge it needs to actually help — correct commands, expected values, environment variables, and decision trees that are specific to Azure HPC GPU SKUs.

## How to Use

### As Copilot custom instructions

Add skills as custom instructions so Copilot has them in context for every chat:

1. Create `.github/copilot-instructions.md` in the repo (or your home directory) referencing the skills you need.
2. Or point to them directly in VS Code settings:

```jsonc
// .vscode/settings.json
{
  "github.copilot.chat.codeGeneration.instructions": [
    { "file": "skills/slurm/sku_performance_baseline.md" },
    { "file": "skills/slurm/nccl_allreduce_test.md" },
    { "file": "skills/slurm/azure_node_health_report.md" }
  ]
}
```

### As chat context (on demand)

Attach a skill to a chat when you need it:

- In VS Code Copilot Chat, use `#file:skills/slurm/nccl_performance_diagnosis.md` to include a specific skill.
- Or drag the file into the chat input.

### As agent skills

If you're building an AI agent (e.g., with Claude, OpenAI, or Azure AI Foundry), load the relevant skill markdown into the agent's system prompt. The skills are written to be directly usable as system prompt context — they contain commands, thresholds, and decision logic, not just descriptions.

## Skills Reference

### Diagnostic — How to run tests and read results

| Skill | What It Covers |
|-------|---------------|
| [sku_performance_baseline](slurm/sku_performance_baseline.md) | Expected NCCL busbw, GPU GFlops, thermal limits, IB ports, and rack sizes for GB300 and H100 SKUs. Warn and GHR thresholds. |
| [node_gpu_validation](slurm/node_gpu_validation.md) | Running ubergemm GEMM benchmarks, parsing CSV output, identifying underperforming GPUs, fleet-wide analysis. |
| [ib_link_validation](slurm/ib_link_validation.md) | Checking IB port state (operstate, ibstat), partition keys, error counters, link flap detection, and soft fixes. |
| [nccl_allreduce_test](slurm/nccl_allreduce_test.md) | Running NCCL all_reduce_perf via the launcher, per-SKU environment variables (MNNVL, SHARP, GDR), output columns, quick vs full sweep. |
| [thermal_stress_test](slurm/thermal_stress_test.md) | Running dcgmproftester thermal stress, interpreting pass/fail, supplementary diagnostics (temperatures, throttle reasons, DCGMI levels). |

### Reasoning — How to analyze and isolate problems

| Skill | What It Covers |
|-------|---------------|
| [nccl_performance_diagnosis](slurm/nccl_performance_diagnosis.md) | Scoping intra-rack vs inter-rack failures, bisection algorithm for isolating bad nodes, GPU vs network root cause analysis. |
| [cluster_outlier_detection](slurm/cluster_outlier_detection.md) | Statistical methods (absolute threshold, z-score, MAD) for finding degraded nodes in fleet-wide test results. |
| [rack_topology](slurm/rack_topology.md) | MNNVL domains, ClusterUUID discovery via nvidia-smi, expected rack sizes, FabricManager troubleshooting. |

### Remediation — How to fix or replace bad hardware

| Skill | What It Covers |
|-------|---------------|
| [azure_node_health_report](slurm/azure_node_health_report.md) | Complete GHR impact category reference (26 categories), collecting PhysicalHostName and Resource ID, REST API format, polling insights. |
| [node_drain_and_replace](slurm/node_drain_and_replace.md) | Slurm drain/undrain commands, reboot procedure, decision tree for when to drain vs reboot vs GHR, post-replacement validation. |

## Example Workflows

### "I just got a new cluster, validate everything"

Skills needed: `sku_performance_baseline`, `rack_topology`, `nccl_allreduce_test`, `node_gpu_validation`, `thermal_stress_test`

1. Discover rack topology (ClusterUUIDs).
2. Run NCCL all_reduce per rack (MNNVL test).
3. Run GPU GEMM test on all nodes.
4. Run thermal stress test on all nodes.
5. Compare results against SKU baselines.

### "A training job is running slow"

Skills needed: `nccl_performance_diagnosis`, `sku_performance_baseline`, `ib_link_validation`

1. Run a quick NCCL check on the job's nodelist.
2. If bandwidth is low, identify which rack is affected.
3. Bisect the failing rack to find the bad node.
4. Check IB links and GPU health on the suspect node.

### "I found a bad node, now what?"

Skills needed: `node_drain_and_replace`, `azure_node_health_report`

1. Collect metadata (PhysicalHostName, Resource ID) **before** rebooting.
2. Drain the node.
3. Attempt reboot if appropriate.
4. If issue persists, file GHR with the correct impact category.
5. Poll insights for resolution status.
