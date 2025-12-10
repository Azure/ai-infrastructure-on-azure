from typing import Any, Dict, List, Optional

from ai_infrastructure_mcp.tools.command_wrapper import run_simple_command

ALLOWED_COMMANDS = {"sacct", "squeue", "sinfo", "scontrol", "sreport", "sbatch"}


def slurm(command: str, args: Optional[List[str]] = None) -> Dict[str, Any]:
    """Execute Slurm commands with argument validation.

    Args:
        command: Slurm command name (sacct, squeue, sinfo, scontrol, sreport, sbatch)
        args: Optional list of arguments to pass to the command
    """
    if command not in ALLOWED_COMMANDS:
        return {
            "version": 1,
            "success": False,
            "command": command,
            "raw_output": "",
            "error": f"Command '{command}' not allowed. Allowed: {', '.join(sorted(ALLOWED_COMMANDS))}",
        }

    # Special handling for sacct with state filter
    processed_args = args
    if command == "sacct" and args:
        processed_args = list(args)
        lowered = [a.lower() for a in processed_args]
        has_state = any(a in ("-s", "--state") for a in lowered) or any(
            a.startswith("--state=") for a in lowered
        )
        has_end = any(a in ("-e", "--endtime") for a in lowered) or any(
            a.startswith("--endtime=") for a in lowered
        )
        if has_state and not has_end:
            processed_args.append("--endtime=now")

    return run_simple_command(command, processed_args)
