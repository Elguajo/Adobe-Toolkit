#!/usr/bin/env python3
"""Conservatively plan and apply individual Launchpad orphan removals."""

from __future__ import annotations

import argparse
import plistlib
import sqlite3
import sys
from pathlib import Path


REQUIRED_COLUMNS = {
    "items": {"rowid"},
    "apps": {"item_id", "title", "bundleid"},
    "image_cache": {"item_id"},
}


def normalize(value: str | None) -> str:
    return (value or "").casefold()


def tsv_value(value: object) -> str:
    return str(value or "").replace("\t", " ").replace("\r", " ").replace("\n", " ") or "-"


def validate(conn: sqlite3.Connection) -> None:
    tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    for table, expected in REQUIRED_COLUMNS.items():
        if table not in tables:
            raise ValueError(f"missing required Launchpad table: {table}")
        columns = {row[1] for row in conn.execute(f"PRAGMA table_info({table})")}
        missing = expected - columns
        if missing:
            raise ValueError(f"unsupported Launchpad schema; {table} lacks {', '.join(sorted(missing))}")


def read_provenance() -> dict[str, tuple[str, str]]:
    records: dict[str, tuple[str, str]] = {}
    for line in sys.stdin:
        bundle_id, sep, rest = line.rstrip("\n").partition("\t")
        if not sep or not bundle_id:
            continue
        title, _, path = rest.partition("\t")
        records[normalize(bundle_id)] = (title, path)
    return records


def plan(db: str, live_ids: list[str], use_provenance_stdin: bool) -> int:
    live = {normalize(value) for value in live_ids if value}
    provenance = read_provenance() if use_provenance_stdin else {}
    try:
        with sqlite3.connect(f"file:{Path(db).resolve()}?mode=ro", uri=True) as conn:
            validate(conn)
            rows = conn.execute("SELECT item_id, title, bundleid FROM apps ORDER BY item_id").fetchall()
    except (sqlite3.Error, OSError, ValueError) as exc:
        print(f"SCHEMA_SKIP\t{str(exc).replace(chr(9), ' ')}")
        return 3

    for item_id, title, bundle_id in rows:
        bundle_key = normalize(bundle_id)
        if not bundle_key or bundle_key in live:
            continue
        if bundle_key.startswith("com.adobe."):
            print(f"REMOVE\t{item_id}\t{tsv_value(title)}\t{tsv_value(bundle_id)}\tmissing Adobe bundle ID has no live registration")
        elif bundle_key in provenance:
            source_title, source_path = provenance[bundle_key]
            reason = f"bundle was recorded before cleanup at {source_path}"
            print(f"REMOVE\t{item_id}\t{tsv_value(title or source_title)}\t{tsv_value(bundle_id)}\t{tsv_value(reason)}")
        else:
            print(f"PRESERVE\t{item_id}\t{tsv_value(title)}\t{tsv_value(bundle_id)}\tmissing non-Adobe bundle has no cleanup provenance")
    return 0


def apply(db: str, item_ids: list[str]) -> int:
    if not item_ids or any(not value.isdigit() for value in item_ids):
        print("APPLY_ERROR\tno valid Launchpad item IDs")
        return 2
    ids = sorted({int(value) for value in item_ids})
    placeholders = ",".join("?" for _ in ids)
    try:
        with sqlite3.connect(db) as conn:
            validate(conn)
            conn.execute("BEGIN IMMEDIATE")
            conn.execute(f"DELETE FROM image_cache WHERE item_id IN ({placeholders})", ids)
            conn.execute(f"DELETE FROM apps WHERE item_id IN ({placeholders})", ids)
            conn.execute(f"DELETE FROM items WHERE rowid IN ({placeholders})", ids)
            conn.commit()
    except (sqlite3.Error, OSError, ValueError) as exc:
        print(f"APPLY_ERROR\t{str(exc).replace(chr(9), ' ')}")
        return 1
    print("APPLY_OK\t" + ",".join(str(value) for value in ids))
    return 0


def capture(paths: list[str]) -> int:
    seen: set[str] = set()
    for raw_path in paths:
        root = Path(raw_path)
        candidates: list[Path] = [root] if root.suffix == ".app" else []
        if root.is_dir() and root.suffix != ".app":
            candidates.extend(path for path in root.rglob("*.app") if path.is_dir())
        for app in candidates:
            plist = app / "Contents" / "Info.plist"
            try:
                with plist.open("rb") as handle:
                    info = plistlib.load(handle)
            except (OSError, plistlib.InvalidFileException):
                continue
            bundle_id = str(info.get("CFBundleIdentifier", "")).strip()
            if not bundle_id or normalize(bundle_id) in seen:
                continue
            seen.add(normalize(bundle_id))
            title = str(info.get("CFBundleDisplayName") or info.get("CFBundleName") or app.stem)
            print("\t".join(value.replace("\t", " ").replace("\n", " ") for value in (bundle_id, title, str(app))))
    return 0


def main() -> None:
    parser = argparse.ArgumentParser()
    subcommands = parser.add_subparsers(dest="command", required=True)
    plan_parser = subcommands.add_parser("plan")
    plan_parser.add_argument("db")
    plan_parser.add_argument("--live-id", action="append", default=[])
    plan_parser.add_argument("--provenance-stdin", action="store_true")
    apply_parser = subcommands.add_parser("apply")
    apply_parser.add_argument("db")
    apply_parser.add_argument("--id", action="append", default=[])
    capture_parser = subcommands.add_parser("capture")
    capture_parser.add_argument("paths", nargs="+")
    args = parser.parse_args()
    if args.command == "plan":
        sys.exit(plan(args.db, args.live_id, args.provenance_stdin))
    if args.command == "apply":
        sys.exit(apply(args.db, args.id))
    sys.exit(capture(args.paths))


if __name__ == "__main__":
    main()
