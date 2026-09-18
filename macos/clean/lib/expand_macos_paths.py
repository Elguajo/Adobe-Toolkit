#!/usr/bin/env python3
"""Print absolute paths to remove (one per line) from manifest.json macos.paths_remove."""
import glob
import json
import os
import sys


def main() -> None:
    if len(sys.argv) < 2:
        print("usage: expand_macos_paths.py MANIFEST.json", file=sys.stderr)
        sys.exit(2)
    path = sys.argv[1]
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    patterns = data.get("macos", {}).get("paths_remove", [])
    seen: set[str] = set()
    for pattern in patterns:
        p = pattern.replace("~", os.path.expanduser("~"), 1) if pattern.startswith("~") else pattern
        if any(c in p for c in "*?["):
            for match in sorted(glob.glob(p)):
                if match not in seen:
                    seen.add(match)
                    print(match)
        else:
            if os.path.lexists(p) and p not in seen:
                seen.add(p)
                print(p)


if __name__ == "__main__":
    main()
