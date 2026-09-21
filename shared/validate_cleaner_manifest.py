#!/usr/bin/env python3
"""Validate the cleaner manifest without a third-party JSON Schema runtime."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


REQUIRED_ARRAYS = {
    "macos": ("kill_patterns", "paths_remove"),
    "windows": ("processes", "services", "paths_remove"),
}
FORBIDDEN_ROOT_TARGETS = {
    "macos": {"/", "~", "$HOME"},
    "windows": {"c:\\", "%userprofile%", "%appdata%", "%localappdata%", "%programfiles%"},
}


def error(errors: list[str], message: str) -> None:
    errors.append(message)


def validate(data: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(data, dict):
        return ["root must be an object"]
    if set(data) != {"version", "macos", "windows"}:
        error(errors, "root must contain exactly version, macos, and windows")
    if data.get("version") != 1:
        error(errors, "version must be 1")

    for platform, keys in REQUIRED_ARRAYS.items():
        section = data.get(platform)
        if not isinstance(section, dict):
            error(errors, f"{platform} must be an object")
            continue
        if set(section) != set(keys):
            error(errors, f"{platform} must contain exactly {', '.join(keys)}")
        for key in keys:
            values = section.get(key)
            label = f"{platform}.{key}"
            if not isinstance(values, list):
                error(errors, f"{label} must be an array")
                continue
            if any(not isinstance(value, str) or not value.strip() for value in values):
                error(errors, f"{label} contains an empty or non-string value")
            if all(isinstance(value, str) for value in values) and len(values) != len(set(values)):
                error(errors, f"{label} contains duplicate entries")
            if key == "paths_remove":
                forbidden = FORBIDDEN_ROOT_TARGETS[platform]
                for value in values:
                    if isinstance(value, str) and value.strip().lower() in forbidden:
                        error(errors, f"{label} contains unsafe root-level target: {value}")
    return errors


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print(f"usage: {Path(sys.argv[0]).name} MANIFEST.json [SCHEMA.json]", file=sys.stderr)
        return 2
    manifest = Path(sys.argv[1])
    schema = Path(sys.argv[2]) if len(sys.argv) == 3 else None
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
        if schema is not None:
            json.loads(schema.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"manifest validation failed: {exc}", file=sys.stderr)
        return 3
    errors = validate(data)
    if errors:
        print("manifest validation failed:", file=sys.stderr)
        for item in errors:
            print(f"- {item}", file=sys.stderr)
        return 3
    print("cleaner manifest is valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
