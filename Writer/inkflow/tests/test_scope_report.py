"""Tests for P0-7: minimal scope report."""

from __future__ import annotations

import pytest
from click.testing import CliRunner
from unittest import mock


class TestScopeReport:
    """P0-7: _print_scope_report should output chapter summary."""

    def test_scope_report_output(self, db, capsys):
        """Scope report should show shot counts and anchor count."""
        import inkflow.cli as cli

        db.execute("INSERT INTO projects (project_id, name) VALUES ('p1', '测试')")
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s1', 'p1', 'run_01', 'active')"
        )
        db.execute(
            "INSERT INTO writing_sessions (session_id, project_id, run_id, status) "
            "VALUES ('s_old', 'p1', 'run_old', 'completed')"
        )
        # Insert shots with different statuses
        for i, (status, light) in enumerate([
            ("done_green", "green"),
            ("done_green", "green"),
            ("done_yellow", "yellow"),
        ]):
            db.execute(
                "INSERT INTO writing_shots "
                "(shot_id, project_id, run_id, layer_key, shot_index, shot_status, light_status) "
                "VALUES (?, 'p1', 'run_01', 'v01.c02', ?, ?, ?)",
                (f"sh{i}", i + 1, status, light),
            )
        db.execute(
            "INSERT INTO writing_shots "
            "(shot_id, project_id, run_id, layer_key, shot_index, shot_status, light_status) "
            "VALUES ('sh_old', 'p1', 'run_old', 'v01.c02', 1, 'done_green', 'green')"
        )
        db.commit()

        # Call the scope report function
        cli._print_scope_report(db, "p1", "s1", "run_01", "v01.c02")

        captured = capsys.readouterr()
        assert "Scope Report" in captured.out
        assert "总 Shot: 3" in captured.out
        assert "Green:   2" in captured.out
        assert "Yellow:  1" in captured.out
