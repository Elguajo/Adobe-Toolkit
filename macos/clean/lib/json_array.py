#!/usr/bin/env python3
"""Print manifest array keys one per line: json_array.py MANIFEST.json windows.services"""
import json
import sys


def main() -> None:
    if len(sys.argv) < 3:
        print("usage: json_array.py MANIFEST.json dot.path", file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f)
    parts = sys.argv[2].split(".")
    cur = data
    for p in parts:
        cur = cur[p]
    if not isinstance(cur, list):
        print("not a list", file=sys.stderr)
        sys.exit(1)
    for item in cur:
        print(item)


if __name__ == "__main__":
    main()
