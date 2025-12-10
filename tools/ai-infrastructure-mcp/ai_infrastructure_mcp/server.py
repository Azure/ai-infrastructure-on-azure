import argparse
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastmcp.server import FastMCP

from .tools.azure_vm import get_physical_hostnames as _get_physical_hostnames_impl
from .tools.azure_vm import get_vmss_id as _get_vmss_instance_name_impl
from .tools.files import count_file as _count_file_impl
from .tools.files import head_file as _head_file_impl
from .tools.files import search_file as _search_file_impl
from .tools.files import tail_file as _tail_file_impl
from .tools.pkeys import get_infiniband_pkeys as _get_infiniband_pkeys_impl
from .tools.slurm import slurm as _slurm_impl
from .tools.systemd import journalctl as _journalctl_impl
from .tools.systemd import systemctl as _systemctl_impl


def build_server() -> FastMCP:
    server = FastMCP(name="ai-infrastructure-mcp")

    @server.tool()
    def get_infiniband_pkeys(hosts: List[str]) -> Dict[str, Any]:  # type: ignore
        """Retrieve InfiniBand partition keys (P_Keys) for each requested host.

        Args:
            hosts: Hostnames to query for InfiniBand P_Keys.
        Returns:
            Structured JSON dict with version, timestamp, hosts[], summary.
        """
        return _get_infiniband_pkeys_impl(hosts)

    @server.tool()
    def get_physical_hostnames(hosts: List[str]) -> Dict[str, Any]:  # type: ignore
        """Retrieve underlying Azure physical hostnames for VMs.

        Extracts the physical host identifier by reading the Hyper-V KVP pool file
        (/var/lib/hyperv/.kvp_pool_3) and applying the provided sed extraction.

        Args:
            hosts: VM hostnames to query (required, non-empty)

        Returns:
            Structured JSON dict with version, timestamp, hosts[], summary.

        Notes:
            - Uses parallel-ssh across provided hosts (same pattern as get_infiniband_pkeys)
            - physical_hostname field may be empty if pattern not present
        """
        return _get_physical_hostnames_impl(hosts)

    @server.tool()
    def get_vmss_instance_name(hosts: List[str]) -> Dict[str, Any]:  # type: ignore
        """Retrieve Azure VMSS (Virtual Machine Scale Set) instance names for VMs.

        Extracts the VMSS instance name from the compute.name field, which is used
        to correlate VM hostnames with Azure Monitor metrics data.

        Args:
            hosts: VM hostnames to query (required, non-empty)

        Returns:
            Structured JSON dict with version, timestamp, hosts[], summary.

        Notes:
            - Uses parallel-ssh across provided hosts (same pattern as get_infiniband_pkeys)
            - vmss_id field may be empty if Azure instance metadata is not accessible
            - VMSS instance names are specifically for Azure Monitor metrics correlation
            - This is NOT the Azure VM ID - use get_physical_hostnames + Kusto for VM IDs
        """
        return _get_vmss_instance_name_impl(hosts)

    @server.tool()
    def slurm(command: str, args: Optional[List[str]] = None) -> Dict[str, Any]:  # type: ignore
        """Execute Slurm commands: sacct, squeue, sinfo, scontrol, sreport, sbatch.

        This unified tool provides access to all Slurm cluster management commands with proper
        argument validation. Specify the command name and pass arguments as a list.

        Args:
            command: Slurm command name (sacct, squeue, sinfo, scontrol, sreport, sbatch)
            args: Optional list of command-line arguments

        Important for squeue:
            Always use short format specifiers (--format=%...) instead of long field names.
            The % codes prevent column truncation and ensure consistent machine-readable output.

        Examples:
            # sacct - Display job accounting data from last 24 hours with parsable format
            slurm('sacct', ['--format=JobID,State,Elapsed', '--starttime=now-1day', '--parsable'])
            
            # sacct - Show failed jobs with error output paths
            slurm('sacct', ['--state=FAILED', '--format=JobID,JobName,StdOut,StdErr', '--starttime=now-1day'])
            
            # squeue - Show all queued jobs with key details (use % format codes)
            slurm('squeue', ['--format=%t,%j,%u,%T,%M,%D,%R'])
            
            # squeue - Show jobs for specific user alice
            slurm('squeue', ['--user', 'alice', '--format=%t,%j,%T,%M'])
            
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
            
            # sbatch - Submit a batch job script
            slurm('sbatch', ['myjob.sh'])
            
            # sbatch - Submit GPU job with specific resources
            slurm('sbatch', ['--partition=gpu', '--nodes=1', '--time=1:00:00', 'gpu_job.sh'])
        """
        return _slurm_impl(command, args)

    @server.tool()
    def systemctl(hosts: List[str], args: Optional[List[str]] = None) -> Dict[str, Any]:  # type: ignore
        """Wrapper for the systemctl command - control systemd services and other units.

        This tool provides access to systemctl functionality for managing systemd services,
        checking service status, and controlling system units on the cluster.

        Args:
            args: Optional list of command-line arguments to pass to systemctl
            hosts: List of hostnames to run the command on (required)

        Examples:
            systemctl(['status', 'ssh']) - Show status of the SSH service
            systemctl(['list-units', '--type=service']) - List all service units
            systemctl(['is-active', 'nginx']) - Check if nginx service is active
            systemctl(['show', 'mysql', '--property=ActiveState']) - Show specific properties
            systemctl(['list-units', '--failed']) - Show only failed units
        """
        return _systemctl_impl(hosts, args)

    @server.tool()
    def journalctl(hosts: List[str], args: Optional[List[str]] = None) -> Dict[str, Any]:  # type: ignore
        """Wrapper for the journalctl command - query and display messages from the journal.

        This tool provides access to systemd journal logs for debugging and monitoring
        system and service activity on the cluster.

        Args:
            args: Optional list of command-line arguments to pass to journalctl
            hosts: List of hostnames to run the command on (required)

        Examples:
            journalctl(['-u', 'ssh', '-n', '10']) - Show last 10 log entries for SSH service
            journalctl(['--since', 'today']) - Show logs since today
            journalctl(['-f', '-u', 'nginx']) - Follow logs for nginx service
            journalctl(['--priority=err']) - Show only error level logs
            journalctl(['--since', '2024-01-01', '--until', '2024-01-02']) - Logs from date range
        """
        return _journalctl_impl(hosts, args)

    @server.tool()
    def head_file(path: str, offset: int = 0, length: int = 10) -> Dict[str, Any]:  # type: ignore
        """Read lines from the beginning of a file with offset and length.

        Args:
            path: Path to the file on the cluster
            offset: Number of lines to skip from the beginning (default: 0)
            length: Number of lines to read (default: 10)

        Returns:
            Structured JSON dict with lines[], line_count, success status, etc.
        """
        return _head_file_impl(path, offset, length)

    @server.tool()
    def tail_file(path: str, offset: int = 0, length: int = 10) -> Dict[str, Any]:  # type: ignore
        """Read lines from the end of a file with offset and length.

        Args:
            path: Path to the file on the cluster
            offset: Number of lines to skip from the end (default: 0)
            length: Number of lines to read (default: 10)

        Returns:
            Structured JSON dict with lines[], line_count, success status, etc.
        """
        return _tail_file_impl(path, offset, length)

    @server.tool()
    def count_file(path: str, mode: str = "lines") -> Dict[str, Any]:  # type: ignore
        """Count lines or bytes in a file.

        Args:
            path: Path to the file on the cluster
            mode: "lines" to count lines, "bytes" to count bytes (default: "lines")

        Returns:
            Structured JSON dict with count, mode, success status, etc.
        """
        return _count_file_impl(path, mode)

    @server.tool()
    def search_file(path: str, pattern: str, before: int = 0, after: int = 0, max_matches: int = 100) -> Dict[str, Any]:  # type: ignore
        """Search for a pattern in a file with context lines.

        Args:
            path: Path to the file on the cluster
            pattern: Regular expression pattern to search for
            before: Number of lines to include before each match (default: 0)
            after: Number of lines to include after each match (default: 0)
            max_matches: Maximum number of matches to return (default: 100)

        Returns:
            Structured JSON dict with matches[], match_count, success status, etc.
        """
        return _search_file_impl(path, pattern, before, after, max_matches)

    return server


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Run ai-infrastructure-mcp server in HTTP or stdio mode."
    )
    parser.add_argument(
        "--mode",
        choices=["http", "stdio"],
        default="stdio",
        help="Server mode: http or stdio (default: stdio)",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8080,
        help="Port to run HTTP server on (default: 8080)",
    )
    parser.add_argument(
        "--host",
        type=str,
        default="127.0.0.1",
        help="Host address to bind HTTP server to (default: 127.0.0.1)",
    )
    args = parser.parse_args()
    server = build_server()
    if args.mode == "stdio":
        server.run()
    else:
        server.run(transport="http", host=args.host, port=args.port)
