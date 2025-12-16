"""File access tools for cluster nodes."""

import shlex
from typing import Any, Dict, Optional, Union

from ai_infrastructure_mcp.ssh_config import run_login_command


def read_file_content(
    path: str,
    action: str = "peek",
    pattern: Optional[str] = None,
    start_line: int = 0,
    end_line: Optional[int] = None,
    limit_lines: int = 10,
    lines_before: int = 0,
    lines_after: int = 0,
    count_mode: Optional[str] = None,
) -> Dict[str, Any]:
    """Retrieves specific content or metadata from a file on the remote cluster.

    The primary operation is controlled by the 'action' parameter:
    - 'peek': Reads a limited, scoped block of lines (like head or tail).
    - 'search': Searches for lines matching a pattern.
    - 'count': Returns the line or byte count (ignores other parameters).

    Args:
        path: Path to the file on the cluster.
        action: The primary mode ('peek', 'search', 'count'). Default is 'peek'.
        pattern: Regular expression pattern to search for (required if action='search'). Uses grep -E (Extended Regex).

        # --- Pythonic Slicing Parameters ---
        start_line: The 0-indexed line number to start reading from (inclusive).
                    Negative indices are supported (e.g., -50 means start 50 lines from the end, like 'tail').
                    (Default: 0)
        end_line: The 0-indexed line number to stop reading at (exclusive).
                  If None, it reads to the end of the file.
                  Negative indices are NOT recommended here; use limit_lines instead.
                  (Default: None)

        # --- Global Limits and Context ---
        limit_lines: A hard cap on the maximum number of lines to return.
                     This limit overrides the range defined by start_line/end_line if the range is larger.
                     **Crucial for context management.** (Default: 10)
        lines_before: Number of context lines to include before each match for the 'search' action.
        lines_after: Number of context lines to include after each match for the 'search' action.

        count_mode: If action='count', use 'lines' or 'bytes' (Optional).

    Returns:
        Structured JSON dict containing results (lines[], count, success status, etc.).
    """
    # Escape the file path for shell safety
    escaped_path = shlex.quote(path)

    if action == "count":
        mode = count_mode if count_mode in ["lines", "bytes"] else "lines"
        cmd = (
            f"wc -l < {escaped_path}" if mode == "lines" else f"wc -c < {escaped_path}"
        )

        try:
            output = run_login_command(cmd)
            if "[stderr]" in output:
                error_part = output.split("[stderr]", 1)[1].strip()
                if "No such file or directory" in error_part:
                    return {"success": False, "error": f"File not found: {path}"}
                elif error_part:
                    return {"success": False, "error": f"Command error: {error_part}"}

            return {
                "success": True,
                "path": path,
                "action": "count",
                "count": int(output.strip()),
                "mode": mode,
            }
        except Exception as e:
            return {"success": False, "error": str(e)}

    elif action == "search":
        if not pattern:
            return {"success": False, "error": "Pattern required for search action"}

        escaped_pattern = shlex.quote(pattern)
        # grep -n for line numbers, -E for extended regex
        cmd_parts = ["grep", "-n", "-E"]
        if lines_before > 0:
            cmd_parts.extend(["-B", str(lines_before)])
        if lines_after > 0:
            cmd_parts.extend(["-A", str(lines_after)])
        # We don't use -m because we want to limit total lines returned, not matches
        # But grep output is complex. Let's just run it and limit output lines.
        cmd_parts.extend([escaped_pattern, escaped_path])

        full_cmd = " ".join(cmd_parts) + f" | head -n {limit_lines}"

        try:
            output = run_login_command(full_cmd)
            if "[stderr]" in output:
                # Check for errors
                parts = output.split("[stderr]", 1)
                stdout = parts[0]
                stderr = parts[1].strip()
                if "No such file or directory" in stderr:
                    return {"success": False, "error": f"File not found: {path}"}
                # Ignore binary file matches warning if we have stdout
                if stderr and not stdout.strip() and "Binary file" not in stderr:
                    return {"success": False, "error": f"Command error: {stderr}"}
                output = stdout

            lines = output.rstrip("\n").split("\n") if output.strip() else []
            return {
                "success": True,
                "path": path,
                "action": "search",
                "pattern": pattern,
                "lines": lines,
            }
        except Exception as e:
            return {"success": False, "error": str(e)}

    elif action == "peek":
        try:
            if start_line >= 0:
                # 1-based start line for sed/tail
                start_1based = start_line + 1
                if end_line is not None:
                    # sed -n 'start,endp'
                    # end_line is exclusive in python slicing, so inclusive in sed is end_line (if 1-based?)
                    # Python: [0, 10) -> 0..9.
                    # 1-based: 1..10.
                    # So end_line (exclusive 0-based) == end_line (inclusive 1-based).
                    # Example: 0:2 -> lines 0, 1. 1-based: 1, 2.
                    cmd = f"sed -n '{start_1based},{end_line}p' {escaped_path}"
                else:
                    cmd = f"tail -n +{start_1based} {escaped_path}"
            else:
                # Negative start_line: tail -n abs(start)
                cmd = f"tail -n {abs(start_line)} {escaped_path}"

            # Apply limit
            cmd += f" | head -n {limit_lines}"

            output = run_login_command(cmd)
            if "[stderr]" in output:
                error_part = output.split("[stderr]", 1)[1].strip()
                if "No such file or directory" in error_part:
                    return {"success": False, "error": f"File not found: {path}"}
                elif error_part:
                    return {"success": False, "error": f"Command error: {error_part}"}

            lines = output.rstrip("\n").split("\n") if output.strip() else []
            return {
                "success": True,
                "path": path,
                "action": "peek",
                "start_line": start_line,
                "end_line": end_line,
                "lines": lines,
            }
        except Exception as e:
            return {"success": False, "error": str(e)}

    return {"success": False, "error": f"Unknown action: {action}"}
