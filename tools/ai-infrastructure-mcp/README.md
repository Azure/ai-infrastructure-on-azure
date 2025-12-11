# AI Infrastructure MCP

This is an MCP server for the AI Infrastructure on Azure project. The initial release focuses on cluster administration and monitoring tools for Slurm clusters.

## Table of Contents

1. [Installation](#1-installation)
2. [Project Layout](#2-project-layout)
3. [Running the Server](#3-running-the-server)
4. [Development Notes](#4-development-notes)
5. [SSH Configuration](#5-ssh-configuration)
6. [Tools](#6-tools)

   6.1 [InfiniBand Tools](#61-infiniband-tools)

   6.2 [Azure VM Tools](#62-azure-vm-tools)

   6.3 [Slurm Tools](#63-slurm-tools)

   6.4 [Systemd Tools](#64-systemd-tools)

   6.5 [File Access Tools](#65-file-access-tools)

7. [Local LLM (Ollama) Setup](#7-local-llm-ollama-setup)

## 1. Installation

It's recommended to use a virtual environment.

Create and activate a venv (Linux/macOS):

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -U pip
```

Install base shared dependency (fastmcp) for development:

```bash
pip install -r requirements.txt
```

## 2. Project Layout

This repository exposes a single MCP server.

```
ai_infrastructure_mcp/       # Unified MCP server package with tools & ssh config
```

## 3. Running the Server

From repo root (after venv + install):

```bash
python -m ai_infrastructure_mcp.server
```

Or via a Model Context Protocol client configuration (see example below).

## 4. Development Notes

- Add new tools under `ai_infrastructure_mcp/tools/` and register them in `server.py` if they need custom wrapping.
- Tests live in `ai_infrastructure_mcp/tests/` and are discovered by `pytest`.

## 5. SSH Configuration

The server reads SSH connection details exclusively from environment variables. No YAML config file is used.

Required env vars:

```
CLUSTER_HOST        # login node hostname
CLUSTER_USER        # SSH username
```

Optional env vars:

```
CLUSTER_PRIVATE_KEY # path to private key (if omitted, SSH agent / default keys are tried)
CLUSTER_PORT        # SSH port (default 22)
```

Example `.vscode/mcp.json` snippet:

```jsonc
{
  "servers": {
    "ai-infrastructure-mcp": {
      "type": "stdio",
      "command": "python",
      "args": ["-m", "ai_infrastructure_mcp.server"],
      "env": {
        "CLUSTER_HOST": "login.cluster.local",
        "CLUSTER_USER": "alice",
        "CLUSTER_PRIVATE_KEY": "/home/alice/.ssh/id_rsa",
        "CLUSTER_PORT": 50022,
      },
    },
  },
}
```

Security notes:

- Use a non-root user.

## 6. Tools

### 6.1 InfiniBand Tools

#### get_infiniband_pkeys

Returns InfiniBand partition keys in a structured JSON object (via parallel-ssh across provided hosts).

Example response:

```json
{
  "version": 1,
  "timestamp": "2025-09-09T12:00:00Z",
  "hosts": [
    { "host": "node01", "pkeys": ["0x7fff", "0x8001"], "error": null },
    { "host": "node02", "pkeys": [], "error": null }
  ],
  "summary": { "queried": 2, "ok": 2, "failed": 0 }
}
```

Notes:

- pkeys list is de-duplicated, lowercase, sorted.
- error field is null on success; a string message on failure.
- summary counts classify a host with any error as failed.

### 6.2 Azure VM Tools

#### get_physical_hostnames

Retrieve the underlying Azure physical hostnames for VMs.

Reads the Hyper-V KVP pool file (`/var/lib/hyperv/.kvp_pool_3`) on each specified host via `parallel-ssh` and extracts
the embedded physical host identifier.

**Robust Implementation:**

- Checks if the Hyper-V file exists before attempting to read it
- Gracefully handles non-Azure VMs by returning empty strings
- Provides error reporting for permission issues and other failures

The command used is equivalent to:

```bash
test -f /var/lib/hyperv/.kvp_pool_3 && tr -d '\0' < /var/lib/hyperv/.kvp_pool_3 | \
  grep -o "Qualified[^V]*VirtualMachineDynamic" | \
  sed "s/Qualified//;s/VirtualMachineDynamic//" | head -1 || echo ""
```

Signature:

```
get_physical_hostnames(hosts: List[str])
```

Example usage:

```
get_physical_hostnames(['vmA','vmB','vmC'])
```

Response includes error handling:

```json
{
  "version": 1,
  "timestamp": "2024-01-01T12:00:00Z",
  "hosts": [
    { "host": "vmA", "physical_hostname": "PHYS_HOST_A" },
    {
      "host": "vmB",
      "physical_hostname": "",
      "error": "tr: /var/lib/hyperv/.kvp_pool_3: Permission denied"
    },
    { "host": "vmC", "physical_hostname": "PHYS_HOST_C" }
  ],
  "summary": { "queried": 3 }
}
```

Notes:

- `physical_hostname` may be empty if pattern not found.
- Follows the same structural pattern as `get_infiniband_pkeys` for consistency.

#### get_vmss_id

Retrieve the Azure VMSS (Virtual Machine Scale Set) ID for a list of VM hosts.

Queries the Azure Instance Metadata Service on each specified host via `parallel-ssh` to extract the `compute.name` field,
which contains the VMSS instance name. This ID is essential for correlating hostnames with Azure Monitor metrics data.

**Implementation Details:**

- Uses Azure Instance Metadata Service endpoint with API version 2025-04-07
- Handles cases where metadata service is not accessible (non-Azure VMs)
- Provides error reporting for curl failures and jq parsing issues
- Returns empty string when metadata field is null or unavailable

The command used is equivalent to:

```bash
curl -H "Metadata: true" "http://169.254.169.254/metadata/instance?api-version=2025-04-07&format=json" 2>/dev/null | \
  jq -r .compute.name 2>/dev/null || echo ""
```

Signature:

```
get_vmss_id(hosts: List[str])
```

Example usage:

```
get_vmss_id(['compute-node-01', 'compute-node-02', 'login-node'])
```

Example response:

```json
{
  "version": 1,
  "timestamp": "2025-01-17T12:00:00Z",
  "hosts": [
    { "host": "compute-node-01", "vmss_id": "compute-sinvqvly6zhmb_5" },
    { "host": "compute-node-02", "vmss_id": "compute-sinvqvly6zhmb_12" },
    { "host": "login-node", "vmss_id": "login-sinvqvly6zhmb_0" }
  ],
  "summary": { "queried": 3 }
}
```

Notes:

- `vmss_id` may be empty if metadata service is not accessible or returns null
- Essential for matching hostnames to Azure Monitor metrics and resource data
- Follows the same structural pattern as other Azure VM tools for consistency

### 6.3 Slurm Tools

#### slurm

Execute Slurm commands with a unified interface. This tool provides access to all major Slurm cluster management commands through a single entry point.

```
slurm(command: str, args: Optional[List[str]] = None)
```

**Allowed commands:** `sacct`, `squeue`, `sinfo`, `scontrol`, `sreport`, `sbatch`

**Important for squeue:**
Always use short format specifiers (`--format=%...`) instead of long field names. The `%` codes prevent column truncation and ensure consistent machine-readable output.

Examples:

```python
# sacct - Display job accounting data from last 24 hours with parsable format
slurm('sacct', ['--format=JobID,State,Elapsed', '--starttime=now-1day', '--parsable'])

# sacct - Show jobs for user alice within date range
slurm('sacct', ['--user', 'alice', '--starttime=2024-01-01', '--endtime=2024-01-02'])

# sacct - Show failed jobs with error output paths
slurm('sacct', ['--state=FAILED', '--format=JobID,JobName,StdOut,StdErr', '--starttime=now-1day'])

# squeue - Show default job queue view
slurm('squeue')

# squeue - Show jobs for specific user
slurm('squeue', ['--user', 'alice'])

# squeue - Show all queued jobs with key details (Job ID, Name, User, State, Time, Nodes, Reason)
slurm('squeue', ['--format=%t,%j,%u,%T,%M,%D,%R'])

# squeue - Filter to only running jobs
slurm('squeue', ['--states=RUNNING', '--format=%t,%j,%u,%T,%M'])

# sinfo - Show default partition and node summary
slurm('sinfo')

# sinfo - Show GPU partition information
slurm('sinfo', ['--partition', 'gpu'])

# sinfo - Custom format showing specific node details
slurm('sinfo', ['--Format', 'NodeList,CPUs,Memory,State'])

# scontrol - Test communication with Slurm controller
slurm('scontrol', ['ping'])

# scontrol - Show detailed information for job 123
slurm('scontrol', ['show', 'job', '123'])

# scontrol - Show node configuration for compute-01
slurm('scontrol', ['show', 'node', 'compute-01'])

# sreport - Generate cluster utilization report
slurm('sreport', ['cluster', 'Utilization'])

# sreport - Show top resource consumers
slurm('sreport', ['user', 'TopUsage'])

# sreport - Job size distribution by account
slurm('sreport', ['job', 'SizesByAccount'])

# sbatch - Submit a batch job script
slurm('sbatch', ['myjob.sh'])

# sbatch - Submit GPU job with specific resources (partition, nodes, time limit)
slurm('sbatch', ['--partition=gpu', '--nodes=1', '--time=1:00:00', 'gpu_job.sh'])
```

Response schema:

```json
{
  "version": 1,
  "success": true,
  "command": "sacct --user alice",
  "raw_output": "...",
  "error": null
}
```

**Notes:**

- Command validation ensures only allowed Slurm commands are executed
- For `sacct` with state filter (`--state` or `-s`) but no explicit `--endtime`, the tool automatically appends `--endtime=now` to ensure results are returned from the current window
- Use `--parsable` with `sacct` for easier parsing of output
- Use `--format=%...` short codes with `squeue` to prevent column truncation

### 6.4 Systemd Tools

#### systemctl

```
systemctl(hosts: List[str], args: Optional[List[str]] = None)
```

Examples:

```
systemctl(['status','ssh'], hosts=['node1'])
systemctl(['is-active','nginx'], hosts=['node1','node2'])
systemctl(['list-units','--failed'], hosts=['nodeA'])
```

Multi-host response shape:

```json
{
  "version": 1,
  "success": true,
  "command": "parallel-ssh -i -H \"node1 node2\" \"systemctl is-active sshd\"",
  "hosts": [
    { "host": "node1", "lines": ["active"] },
    { "host": "node2", "lines": ["inactive"] }
  ],
  "raw_output": "[1] ...",
  "error": null,
  "summary": { "queried": 2 }
}
```

#### journalctl

```
journalctl(hosts: List[str], args: Optional[List[str]] = None)
```

Examples:

```
journalctl(['-u','ssh','-n','20'], hosts=['node1'])
journalctl(['-u','sshd','-n','5'], hosts=['node1','node2'])
journalctl(['--priority=err','-n','50'], hosts=['nodeA','nodeB','nodeC'])
```

Response schema matches the `systemctl` multi-host example above.

Notes:

- Only simple command argument lists are allowed; no shell pipelines are constructed for systemd tools.
- Hostnames failing validation raise `ValueError`.

### 6.5 File Access Tools

#### read_file_content

Retrieves specific content or metadata from a file on the remote cluster.

Parameters:

- `path` (string): Path to the file on the cluster
- `action` (string, default: "peek"): Primary mode ('peek', 'search', 'count')
- `pattern` (string, optional): Regex pattern (required for 'search')
- `start_line` (int, default: 0): 0-indexed start line (inclusive). Negative values supported (e.g. -50).
- `end_line` (int, optional): 0-indexed end line (exclusive).
- `limit_lines` (int, default: 10): Hard cap on lines returned.
- `lines_before` (int, default: 0): Context lines before match (for 'search').
- `lines_after` (int, default: 0): Context lines after match (for 'search').
- `count_mode` (string, optional): 'lines' or 'bytes' (for 'count').

Example response (peek):

```json
{
  "success": true,
  "path": "/path/to/file.log",
  "action": "peek",
  "start_line": 0,
  "end_line": 10,
  "lines": ["line 1", "line 2", "..."]
}
```

Example response (search):

```json
{
  "success": true,
  "path": "/path/to/file.log",
  "action": "search",
  "pattern": "ERROR",
  "lines": ["ERROR: Something went wrong"]
}
```

Example response (count):

```json
{
  "success": true,
  "path": "/path/to/file.log",
  "action": "count",
  "count": 1000,
  "mode": "lines"
}
```

**File Access Security Notes:**

- All file paths are properly escaped to prevent command injection
- File access is limited to what the SSH user can access on the cluster
- Large files can be read in chunks using offset/length parameters to avoid filling context windows
- Search operations are limited by max_matches to prevent excessive output

## 7. Local LLM (Ollama) Setup

Run a local Ollama instance (e.g. on an Azure NDv5 / GPU node) and point VS Code Copilot to it for fully local model inference.

### Use Local NVMe for Docker Data

Move Docker's data-root onto fast local NVMe to avoid filling OS disk and to speed up model layer extraction.

1. Stop Docker:

```bash
sudo systemctl stop docker
```

2. Edit `/etc/docker/daemon.json` (create if missing) and add or merge:

```jsonc
{
  "data-root": "/mnt/nvme/docker-data",
}
```

3. Ensure the directory exists and proper ownership:

```bash
sudo mkdir -p /mnt/nvme/docker-data
sudo chown root:root /mnt/nvme/docker-data
```

4. Start Docker:

```bash
sudo systemctl start docker
```

### Run Ollama Container

Pull and run the latest Ollama container with GPU access:

```bash
IMAGE="ollama/ollama:latest"
CONTAINER_NAME="ollama_llm"
PORT=11434
sudo docker run --gpus=all --shm-size=1g \
  -v $HOME/ollama_data:/root/.ollama \
  -p ${PORT}:11434 \
  --name $CONTAINER_NAME $IMAGE
```

If you need to restart later:

```bash
sudo docker start ollama_llm
```

### Pre-Pull Models

Download the required models before first use in VS Code (examples shown):

```bash
sudo docker exec -it ollama_llm ollama pull llama2:70b
sudo docker exec -it ollama_llm ollama pull gpt-oss:120b
```

Adjust model names/sizes to what your GPU memory can support.

### Using with VS Code Copilot (Ollama Provider)

1. Open the Copilot chat panel.
2. Click the model dropdown and choose "Manage models...".
3. Select the Ollama provider and pick a local model (e.g. `gpt-oss` or `llama2`).
4. The agent will now route requests to your local Ollama endpoint on `http://localhost:11434`.

Notes:

- Ensure the VS Code environment can reach the GPU host (if remote, use SSH remote dev so localhost maps through the tunnel).
- Large model pulls can take significant time; monitor progress with `docker logs -f ollama_llm`.
- To remove the container & data: `docker rm -f ollama_llm && rm -rf $HOME/ollama_data` (irreversible).
