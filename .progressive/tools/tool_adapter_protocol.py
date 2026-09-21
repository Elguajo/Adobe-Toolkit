#!/usr/bin/env python3
"""Validate the Progressive Context Tool Adapter Protocol registry."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from urllib.parse import urlparse

REQUIRED_TOOL_FIELDS = {
    "brand",
    "capability",
    "preferred_for",
    "avoid_when",
    "official",
    "probe_commands",
    "fallback",
    "profiles",
    "extra_approval_required_for",
}
ALLOWED_PROFILES = {"recommended", "advanced_spec"}
REQUIRED_DEFAULTS = {
    "installation_source": "current official documentation",
    "context_loading": "on_demand",
    "invoke_only_when_materially_useful": True,
    "installation_or_user_global_config_requires_approval": True,
}


def integration_dir(root: Path) -> Path:
    source = root / "integrations"
    # Real product repositories may own a root integrations/ directory. Treat the
    # source surface as canonical only when the framework-specific registry exists.
    if (source / "TOOL_REGISTRY.json").is_file():
        return source
    return root / ".progressive" / "integrations"


def _nonempty_string(value) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _string_list(value, *, allow_empty: bool) -> bool:
    if not isinstance(value, list):
        return False
    if not allow_empty and not value:
        return False
    return all(_nonempty_string(item) for item in value) and len(value) == len(set(value))


def validate(root: Path) -> tuple[list[str], list[str]]:
    root = root.resolve()
    errors: list[str] = []
    warns: list[str] = []
    integrations = integration_dir(root)
    registry_path = integrations / "TOOL_REGISTRY.json"
    protocol_path = integrations / "TOOL_ADAPTER_PROTOCOL.md"
    if not registry_path.is_file():
        return ["missing Tool Adapter Registry"], warns
    if not protocol_path.is_file():
        return ["missing Tool Adapter Protocol"], warns

    try:
        data = json.loads(registry_path.read_text(encoding="utf-8"))
    except Exception as exc:
        return [f"invalid TOOL_REGISTRY.json: {exc}"], warns

    if data.get("schema") != 2:
        errors.append("TOOL_REGISTRY schema must be 2")
    if data.get("adapter_contract_version") != 1:
        errors.append("adapter_contract_version must be 1")

    defaults = data.get("adapter_defaults")
    if not isinstance(defaults, dict):
        errors.append("adapter_defaults must be an object")
    else:
        for key, expected in REQUIRED_DEFAULTS.items():
            if defaults.get(key) != expected:
                errors.append(f"adapter_defaults.{key} must equal {expected!r}")

    tools = data.get("tools")
    if not isinstance(tools, dict) or not tools:
        errors.append("tools must be a non-empty object")
        return errors, warns

    for key, tool in tools.items():
        prefix = f"tools.{key}"
        if not isinstance(tool, dict):
            errors.append(f"{prefix} must be an object")
            continue
        missing = REQUIRED_TOOL_FIELDS - set(tool)
        if missing:
            errors.append(f"{prefix} missing fields: {', '.join(sorted(missing))}")
            continue
        for field in ("brand", "capability", "fallback"):
            if not _nonempty_string(tool.get(field)):
                errors.append(f"{prefix}.{field} must be a non-empty string")
        if not _string_list(tool.get("preferred_for"), allow_empty=False):
            errors.append(f"{prefix}.preferred_for must be a unique non-empty string array")
        if not _string_list(tool.get("avoid_when"), allow_empty=False):
            errors.append(f"{prefix}.avoid_when must be a unique non-empty string array")
        if not _string_list(tool.get("probe_commands"), allow_empty=True):
            errors.append(f"{prefix}.probe_commands must be a unique string array")
        if not _string_list(tool.get("extra_approval_required_for"), allow_empty=True):
            errors.append(f"{prefix}.extra_approval_required_for must be a unique string array")
        profiles = tool.get("profiles")
        if not _string_list(profiles, allow_empty=False):
            errors.append(f"{prefix}.profiles must be a unique non-empty string array")
        elif not set(profiles) <= ALLOWED_PROFILES:
            errors.append(f"{prefix}.profiles contains unknown profile")
        official = tool.get("official")
        if not _nonempty_string(official):
            errors.append(f"{prefix}.official must be a non-empty URL")
        else:
            parsed = urlparse(official)
            if parsed.scheme != "https" or not parsed.netloc:
                errors.append(f"{prefix}.official must be an https URL")

    return errors, warns


def main() -> int:
    ap = argparse.ArgumentParser(description="Validate Tool Adapter Protocol conformance.")
    ap.add_argument("--root", default=".")
    args = ap.parse_args()
    root = Path(args.root).resolve()
    errors, warns = validate(root)
    for item in errors:
        print("ERROR:", item)
    for item in warns:
        print("WARN:", item)
    if errors:
        print(f"TOOL ADAPTER PROTOCOL: FAIL ({len(errors)} errors, {len(warns)} warnings)")
        return 1
    data = json.loads((integration_dir(root) / "TOOL_REGISTRY.json").read_text(encoding="utf-8"))
    print(f"TOOL ADAPTER PROTOCOL: PASS ({len(data['tools'])} adapters)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
