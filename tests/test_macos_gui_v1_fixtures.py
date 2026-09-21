#!/usr/bin/env python3
"""Safety fixtures for the planned macOS GUI v1 adapter boundary.

The suite uses a test-only in-memory backend and writes any fixture copies or
sentinels beneath ``TemporaryDirectory``.  It deliberately never starts a
real cleaner, Launch Services, Launchpad, sudo, or a real Adobe-data workflow.
"""

from __future__ import annotations

import json
import tempfile
import unittest
from dataclasses import dataclass
from pathlib import Path
from typing import Any


FIXTURES = Path(__file__).with_name("fixtures") / "macos_gui_v1"

SUPPORTED_OPERATIONS = frozenset(
    {
        "backup.scan",
        "backup.create",
        "restore.validate",
        "restore.apply",
        "cleanup.preview",
        "diagnose.run",
    }
)
UNSUPPORTED_OPERATIONS = frozenset({"cleanup.apply", "repair.preview", "repair.apply"})
STATUSES = frozenset(
    {"success", "cancelled", "invalid", "unavailable", "unsupported", "partial", "failed"}
)


@dataclass(frozen=True)
class GuiResult:
    state: str
    is_success: bool
    report: dict[str, Any] | None = None


class FakeBackend:
    """Records typed adapter requests without creating a process."""

    def __init__(self, responses: dict[str, bytes]) -> None:
        self.responses = responses
        self.requests: list[str] = []

    def invoke(self, operation: str) -> bytes:
        self.requests.append(operation)
        return self.responses[operation]


class GuiV1FixtureAdapter:
    """Test model of the v1 GUI safety boundary, not a shell executor."""

    def __init__(self, backend: FakeBackend) -> None:
        self.backend = backend
        self.authorization_requests = 0

    def run(self, operation: str) -> GuiResult:
        if operation in UNSUPPORTED_OPERATIONS:
            return GuiResult(state="unsupported", is_success=False)
        if operation not in SUPPORTED_OPERATIONS:
            return GuiResult(state="unavailable", is_success=False)

        try:
            report = json.loads(self.backend.invoke(operation).decode("utf-8"))
            self._validate_report(operation, report)
        except (KeyError, UnicodeDecodeError, json.JSONDecodeError, ValueError, TypeError):
            return GuiResult(state="failed", is_success=False)

        return GuiResult(state=report["status"], is_success=report["status"] == "success", report=report)

    @staticmethod
    def _validate_report(operation: str, report: object) -> None:
        if not isinstance(report, dict):
            raise ValueError("result must be an object")
        required_types: dict[str, type | tuple[type, ...]] = {
            "schemaVersion": int,
            "operation": str,
            "status": str,
            "exitCode": int,
            "mutates": bool,
            "summary": dict,
            "items": list,
            "warnings": list,
            "errors": list,
            "logPath": (str, type(None)),
        }
        if any(not isinstance(report.get(field), expected) for field, expected in required_types.items()):
            raise ValueError("result has invalid fields")
        if isinstance(report["exitCode"], bool):
            raise ValueError("exitCode must be an integer")
        if report["schemaVersion"] != 1 or report["operation"] != operation or report["status"] not in STATUSES:
            raise ValueError("result is incompatible with v1")
        if (report["status"] == "success") != (report["exitCode"] == 0):
            raise ValueError("status and exit code are inconsistent")
        if operation == "cleanup.preview" and report["mutates"]:
            raise ValueError("cleanup preview must be non-mutating")


def fixture_bytes(name: str, temporary_root: Path) -> bytes:
    """Copy a repository fixture into the test temporary directory before use."""

    copied_fixture = temporary_root / name
    copied_fixture.write_bytes((FIXTURES / name).read_bytes())
    return copied_fixture.read_bytes()


def tree_snapshot(root: Path) -> dict[str, bytes]:
    return {
        str(path.relative_to(root)): path.read_bytes()
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


class MacosGuiV1FixtureTests(unittest.TestCase):
    def test_cleanup_preview_is_immutable(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            adobe_data = root / "home/Library/Preferences/com.adobe.fixture.plist"
            adobe_data.parent.mkdir(parents=True)
            adobe_data.write_text("preserve", encoding="utf-8")
            launch_services = root / "home/Library/Preferences/com.apple.LaunchServices.plist"
            launch_services.write_text("preserve", encoding="utf-8")
            launchpad = root / "home/Library/Application Support/Dock/desktoppicture.db"
            launchpad.parent.mkdir(parents=True)
            launchpad.write_text("preserve", encoding="utf-8")

            response = fixture_bytes("cleanup-preview-success.json", root)
            before = tree_snapshot(root)
            backend = FakeBackend({"cleanup.preview": response})
            result = GuiV1FixtureAdapter(backend).run("cleanup.preview")

            self.assertTrue(result.is_success)
            self.assertFalse(result.report["mutates"] if result.report else True)
            self.assertEqual(backend.requests, ["cleanup.preview"])
            self.assertEqual(tree_snapshot(root), before)

    def test_full_cleanup_and_repair_are_unsupported_without_backend_or_authorization(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            backend = FakeBackend({})
            adapter = GuiV1FixtureAdapter(backend)

            for operation in sorted(UNSUPPORTED_OPERATIONS):
                with self.subTest(operation=operation):
                    result = adapter.run(operation)
                    self.assertEqual(result.state, "unsupported")
                    self.assertFalse(result.is_success)

            self.assertEqual(backend.requests, [])
            self.assertEqual(adapter.authorization_requests, 0)

    def test_backend_failure_never_produces_success_notification(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            backend = FakeBackend(
                {"diagnose.run": fixture_bytes("diagnose-failed.json", root)}
            )

            result = GuiV1FixtureAdapter(backend).run("diagnose.run")

            self.assertEqual(result.state, "failed")
            self.assertFalse(result.is_success)
            self.assertEqual(backend.requests, ["diagnose.run"])

    def test_cancellation_is_retained_without_success(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            backend = FakeBackend(
                {"backup.scan": fixture_bytes("backup-scan-cancelled.json", root)}
            )

            result = GuiV1FixtureAdapter(backend).run("backup.scan")

            self.assertEqual(result.state, "cancelled")
            self.assertFalse(result.is_success)
            self.assertEqual(result.report["exitCode"] if result.report else None, 2)

    def test_malformed_or_inconsistent_result_is_failed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            inconsistent = json.dumps(
                {
                    "schemaVersion": 1,
                    "operation": "cleanup.preview",
                    "status": "success",
                    "exitCode": 7,
                    "mutates": False,
                    "summary": {},
                    "items": [],
                    "warnings": [],
                    "errors": [],
                    "logPath": None,
                }
            ).encode("utf-8")
            mutating_preview = json.dumps(
                {
                    "schemaVersion": 1,
                    "operation": "cleanup.preview",
                    "status": "success",
                    "exitCode": 0,
                    "mutates": True,
                    "summary": {},
                    "items": [],
                    "warnings": [],
                    "errors": [],
                    "logPath": None,
                }
            ).encode("utf-8")

            for label, response in {
                "malformed JSON": fixture_bytes("malformed-result.json", root),
                "inconsistent status and exit code": inconsistent,
                "mutating cleanup preview": mutating_preview,
            }.items():
                with self.subTest(label=label):
                    backend = FakeBackend({"cleanup.preview": response})
                    result = GuiV1FixtureAdapter(backend).run("cleanup.preview")
                    self.assertEqual(result.state, "failed")
                    self.assertFalse(result.is_success)
                    self.assertEqual(backend.requests, ["cleanup.preview"])


if __name__ == "__main__":
    unittest.main()
