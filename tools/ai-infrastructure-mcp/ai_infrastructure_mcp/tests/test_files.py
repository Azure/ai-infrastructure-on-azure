"""Tests for the unified read_file_content() function.

The files module exposes a single `read_file_content(path, action, ...)` function
that supports 'peek', 'search', and 'count' actions.
"""

import ai_infrastructure_mcp.tools.files as files


def test_peek_basic(monkeypatch):
    """Test basic peek functionality (read first N lines)."""
    sample = "line 1\nline 2\nline 3"

    def fake_run(cmd: str):
        assert "head -n" in cmd
        assert "/test/file" in cmd
        return sample

    monkeypatch.setattr(files, "run_login_command", fake_run)

    result = files.read_file_content("/test/file", action="peek", limit_lines=3)
    assert result["success"] is True
    assert result["path"] == "/test/file"
    assert result["action"] == "peek"
    assert result["lines"] == ["line 1", "line 2", "line 3"]


def test_peek_with_start_line(monkeypatch):
    """Test peek with positive start_line (skip lines)."""
    sample = "line 3\nline 4"

    def fake_run(cmd: str):
        # Should use tail -n +N to skip lines
        assert "tail -n +3" in cmd or "sed -n" in cmd
        return sample

    monkeypatch.setattr(files, "run_login_command", fake_run)

    result = files.read_file_content(
        "/test/file", action="peek", start_line=2, limit_lines=2
    )
    assert result["success"] is True
    assert result["lines"] == ["line 3", "line 4"]


def test_peek_with_negative_start_line(monkeypatch):
    """Test peek with negative start_line (tail from end)."""
    sample = "line 8\nline 9\nline 10"

    def fake_run(cmd: str):
        # Negative start means tail -n abs(start)
        assert "tail -n 3" in cmd
        return sample

    monkeypatch.setattr(files, "run_login_command", fake_run)

    result = files.read_file_content(
        "/test/file", action="peek", start_line=-3, limit_lines=10
    )
    assert result["success"] is True
    assert result["lines"] == ["line 8", "line 9", "line 10"]


def test_peek_file_not_found(monkeypatch):
    """Test peek with non-existent file."""

    def fake_run(cmd: str):
        return "stdout\n[stderr]\nNo such file or directory"

    monkeypatch.setattr(files, "run_login_command", fake_run)

    result = files.read_file_content("/nonexistent", action="peek")
    assert result["success"] is False
    assert "File not found" in result["error"]


def test_search_basic(monkeypatch):
    """Test basic search functionality."""
    grep_output = "3:found pattern here\n5:another pattern match"

    def fake_run(cmd: str):
        assert "grep -n" in cmd
        assert "pattern" in cmd
        return grep_output

    monkeypatch.setattr(files, "run_login_command", fake_run)

    result = files.read_file_content("/test/file", action="search", pattern="pattern")
    assert result["success"] is True
    assert result["action"] == "search"
    assert result["pattern"] == "pattern"
    assert len(result["lines"]) == 2


def test_search_with_context(monkeypatch):
    """Test search with before/after context lines."""

    def fake_run(cmd: str):
        assert "-B 2" in cmd
        assert "-A 1" in cmd
        return "1-before1\n2-before2\n3:match\n4-after"

    monkeypatch.setattr(files, "run_login_command", fake_run)

    result = files.read_file_content(
        "/test/file", action="search", pattern="match", lines_before=2, lines_after=1
    )
    assert result["success"] is True


def test_search_no_pattern():
    """Test search without pattern returns error."""
    result = files.read_file_content("/test/file", action="search")
    assert result["success"] is False
    assert "Pattern required" in result["error"]


def test_search_no_matches(monkeypatch):
    """Test search with no matches."""

    def fake_run(cmd: str):
        return ""  # grep returns empty on no match

    monkeypatch.setattr(files, "run_login_command", fake_run)

    result = files.read_file_content(
        "/test/file", action="search", pattern="nonexistent"
    )
    assert result["success"] is True
    assert result["lines"] == []


def test_search_file_not_found(monkeypatch):
    """Test search with non-existent file."""

    def fake_run(cmd: str):
        return "[stderr]\ngrep: /nonexistent: No such file or directory"

    monkeypatch.setattr(files, "run_login_command", fake_run)

    result = files.read_file_content("/nonexistent", action="search", pattern="test")
    assert result["success"] is False
    assert "File not found" in result["error"]


def test_count_lines(monkeypatch):
    """Test count action with lines mode."""

    def fake_run(cmd: str):
        assert "wc -l" in cmd
        return "42"

    monkeypatch.setattr(files, "run_login_command", fake_run)

    result = files.read_file_content("/test/file", action="count", count_mode="lines")
    assert result["success"] is True
    assert result["action"] == "count"
    assert result["count"] == 42
    assert result["mode"] == "lines"


def test_count_bytes(monkeypatch):
    """Test count action with bytes mode."""

    def fake_run(cmd: str):
        assert "wc -c" in cmd
        return "1024"

    monkeypatch.setattr(files, "run_login_command", fake_run)

    result = files.read_file_content("/test/file", action="count", count_mode="bytes")
    assert result["success"] is True
    assert result["count"] == 1024
    assert result["mode"] == "bytes"


def test_count_default_mode(monkeypatch):
    """Test count defaults to lines mode."""

    def fake_run(cmd: str):
        assert "wc -l" in cmd
        return "100"

    monkeypatch.setattr(files, "run_login_command", fake_run)

    result = files.read_file_content("/test/file", action="count")
    assert result["success"] is True
    assert result["mode"] == "lines"


def test_count_file_not_found(monkeypatch):
    """Test count with non-existent file."""

    def fake_run(cmd: str):
        return "[stderr]\nNo such file or directory"

    monkeypatch.setattr(files, "run_login_command", fake_run)

    result = files.read_file_content("/nonexistent", action="count")
    assert result["success"] is False
    assert "File not found" in result["error"]


def test_invalid_action():
    """Test unknown action returns error."""
    result = files.read_file_content("/test/file", action="invalid")
    assert result["success"] is False
    assert "Unknown action" in result["error"]


def test_file_path_escaping(monkeypatch):
    """Test that file paths with special characters are properly escaped."""

    def fake_run(cmd: str):
        # shlex.quote should wrap the path
        assert "'file with spaces & symbols.txt'" in cmd
        return "test output"

    monkeypatch.setattr(files, "run_login_command", fake_run)

    result = files.read_file_content("file with spaces & symbols.txt", action="peek")
    assert result["success"] is True


def test_pattern_escaping(monkeypatch):
    """Test that search patterns with special characters are properly escaped."""

    def fake_run(cmd: str):
        # Pattern should be quoted
        assert "'special $pattern [with] chars'" in cmd
        return ""

    monkeypatch.setattr(files, "run_login_command", fake_run)

    result = files.read_file_content(
        "/test/file", action="search", pattern="special $pattern [with] chars"
    )
    assert result["success"] is True


def test_empty_file(monkeypatch):
    """Test handling of empty files."""

    def fake_run(cmd: str):
        return ""

    monkeypatch.setattr(files, "run_login_command", fake_run)

    result = files.read_file_content("/empty/file", action="peek")
    assert result["success"] is True
    assert result["lines"] == []


def test_limit_lines_applied(monkeypatch):
    """Test that limit_lines is applied to output."""

    def fake_run(cmd: str):
        assert "head -n 5" in cmd
        return "line1\nline2\nline3\nline4\nline5"

    monkeypatch.setattr(files, "run_login_command", fake_run)

    result = files.read_file_content("/test/file", action="peek", limit_lines=5)
    assert result["success"] is True
    assert len(result["lines"]) == 5
