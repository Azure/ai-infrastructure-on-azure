"""Shell command execution tool."""

from typing import Any, Dict

from ai_infrastructure_mcp.ssh_config import run_login_command


def run_command(command: str) -> Dict[str, Any]:
    """Run a shell command on the remote cluster.

    Args:
        command: The shell command to execute.

    Returns:
        Structured JSON dict with stdout, stderr, success status.
    """
    try:
        output = run_login_command(command)

        stdout = output
        stderr = ""

        # Check for stderr in output (ssh_config.run_login_command appends it)
        if "[stderr]" in output:
            parts = output.split("[stderr]", 1)
            stdout = parts[0]
            stderr = parts[1].strip()

        return {
            "success": True,
            "command": command,
            "stdout": stdout,
            "stderr": stderr,
        }

    except Exception as e:
        return {
            "success": False,
            "command": command,
            "error": str(e),
            "stdout": "",
            "stderr": "",
        }
