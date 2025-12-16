"""Tests for the unified slurm() function.

The slurm module exposes a single `slurm(command, args)` function that
validates the command name and delegates to run_simple_command.
"""

import ai_infrastructure_mcp.tools.command_wrapper as command_wrapper
import ai_infrastructure_mcp.tools.slurm as slurm_module


def test_slurm_sacct_no_args(monkeypatch):
    """Test slurm('sacct') with no arguments."""

    def fake_run(cmd: str):
        assert cmd == "sacct"
        return "mock sacct output"

    monkeypatch.setattr(command_wrapper, "run_login_command", fake_run)
    result = slurm_module.slurm("sacct")

    assert result["success"] is True
    assert result["raw_output"] == "mock sacct output"
    assert result["command"] == "sacct"


def test_slurm_sacct_with_args(monkeypatch):
    """Test slurm('sacct', args) with argument list (auto endtime)."""

    def fake_run(cmd: str):
        # --endtime=now should be auto-appended when --state is present without --endtime
        assert cmd == "sacct --user alice --state FAILED --endtime=now"
        return "mock sacct output"

    monkeypatch.setattr(command_wrapper, "run_login_command", fake_run)
    result = slurm_module.slurm("sacct", ["--user", "alice", "--state", "FAILED"])

    assert result["success"] is True
    assert result["raw_output"] == "mock sacct output"


def test_slurm_sacct_with_endtime_no_append(monkeypatch):
    """Test that --endtime is NOT appended if already provided."""

    def fake_run(cmd: str):
        # Should NOT add another --endtime=now
        assert cmd == "sacct --state FAILED --endtime=2024-01-01"
        return "mock output"

    monkeypatch.setattr(command_wrapper, "run_login_command", fake_run)
    result = slurm_module.slurm("sacct", ["--state", "FAILED", "--endtime=2024-01-01"])

    assert result["success"] is True


def test_slurm_squeue_no_args(monkeypatch):
    """Test slurm('squeue') with no arguments."""

    def fake_run(cmd: str):
        assert cmd == "squeue"
        return "mock squeue output"

    monkeypatch.setattr(command_wrapper, "run_login_command", fake_run)
    result = slurm_module.slurm("squeue")

    assert result["success"] is True
    assert result["raw_output"] == "mock squeue output"
    assert result["command"] == "squeue"


def test_slurm_squeue_with_args(monkeypatch):
    """Test slurm('squeue', args) with argument list."""

    def fake_run(cmd: str):
        assert cmd == "squeue --user alice --states RUNNING"
        return "mock squeue output"

    monkeypatch.setattr(command_wrapper, "run_login_command", fake_run)
    result = slurm_module.slurm("squeue", ["--user", "alice", "--states", "RUNNING"])

    assert result["success"] is True
    assert result["raw_output"] == "mock squeue output"


def test_slurm_sinfo_no_args(monkeypatch):
    """Test slurm('sinfo') with no arguments."""

    def fake_run(cmd: str):
        assert cmd == "sinfo"
        return "mock sinfo output"

    monkeypatch.setattr(command_wrapper, "run_login_command", fake_run)
    result = slurm_module.slurm("sinfo")

    assert result["success"] is True
    assert result["raw_output"] == "mock sinfo output"


def test_slurm_scontrol_show_job(monkeypatch):
    """Test slurm('scontrol', ['show', 'job', '123'])."""

    def fake_run(cmd: str):
        assert cmd == "scontrol show job 123"
        return "JobId=123 ..."

    monkeypatch.setattr(command_wrapper, "run_login_command", fake_run)
    result = slurm_module.slurm("scontrol", ["show", "job", "123"])

    assert result["success"] is True


def test_slurm_sreport_cluster_utilization(monkeypatch):
    """Test slurm('sreport', ['cluster', 'Utilization'])."""

    def fake_run(cmd: str):
        assert cmd == "sreport cluster Utilization"
        return "Cluster Utilization..."

    monkeypatch.setattr(command_wrapper, "run_login_command", fake_run)
    result = slurm_module.slurm("sreport", ["cluster", "Utilization"])

    assert result["success"] is True


def test_slurm_sbatch_submit(monkeypatch):
    """Test slurm('sbatch', ['myjob.sh'])."""

    def fake_run(cmd: str):
        assert cmd == "sbatch myjob.sh"
        return "Submitted batch job 12345"

    monkeypatch.setattr(command_wrapper, "run_login_command", fake_run)
    result = slurm_module.slurm("sbatch", ["myjob.sh"])

    assert result["success"] is True
    assert "12345" in result["raw_output"]


def test_slurm_invalid_command():
    """Test that invalid commands are rejected."""
    result = slurm_module.slurm("rm", ["-rf", "/"])

    assert result["success"] is False
    assert "not allowed" in result["error"]
    assert "rm" in result["error"]


def test_slurm_injection_safety(monkeypatch):
    """Test that dangerous characters in arguments are properly quoted."""

    def fake_run(cmd: str):
        # Verify dangerous characters are properly quoted
        assert cmd == "sacct --user 'alice; rm -rf /'"
        return "mock output"

    monkeypatch.setattr(command_wrapper, "run_login_command", fake_run)
    result = slurm_module.slurm("sacct", ["--user", "alice; rm -rf /"])

    assert result["success"] is True


def test_slurm_error_handling(monkeypatch):
    """Test error handling when command execution fails."""

    def fake_run(cmd: str):
        raise Exception("Connection failed")

    monkeypatch.setattr(command_wrapper, "run_login_command", fake_run)
    result = slurm_module.slurm("squeue")

    assert result["success"] is False
    assert "Connection failed" in result["error"]


def test_slurm_none_args(monkeypatch):
    """Test that None args is handled correctly (same as no args)."""

    def fake_run(cmd: str):
        assert cmd == "sinfo"
        return "mock output"

    monkeypatch.setattr(command_wrapper, "run_login_command", fake_run)
    result = slurm_module.slurm("sinfo", None)

    assert result["success"] is True


def test_slurm_empty_args(monkeypatch):
    """Test that empty args list is handled correctly (same as no args)."""

    def fake_run(cmd: str):
        assert cmd == "sinfo"
        return "mock output"

    monkeypatch.setattr(command_wrapper, "run_login_command", fake_run)
    result = slurm_module.slurm("sinfo", [])

    assert result["success"] is True


def test_slurm_complex_format_string(monkeypatch):
    """Test complex format strings with special characters."""

    def fake_run(cmd: str):
        assert cmd == "squeue --format '%i %t %j %u %T %M %l %D %R'"
        return "mock output"

    monkeypatch.setattr(command_wrapper, "run_login_command", fake_run)
    result = slurm_module.slurm("squeue", ["--format", "%i %t %j %u %T %M %l %D %R"])

    assert result["success"] is True


def test_slurm_result_structure(monkeypatch):
    """Test that the result has the expected structure."""

    def fake_run(cmd: str):
        return "test output"

    monkeypatch.setattr(command_wrapper, "run_login_command", fake_run)
    result = slurm_module.slurm("sinfo")

    assert "version" in result
    assert "success" in result
    assert "command" in result
    assert "raw_output" in result
    assert "error" in result
    assert result["version"] == 1
