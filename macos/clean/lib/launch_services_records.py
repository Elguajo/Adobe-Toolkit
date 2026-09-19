#!/usr/bin/env python3
"""Extract missing Adobe and live application registrations from lsregister -dump."""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass


@dataclass
class Record:
    bundle_id: str = ""
    canonical_id: str = ""
    name: str = ""
    path: str = ""


FIELD_RE = re.compile(r"^\s*(bundle id|identifier|canonical id|name|path):\s*(.*?)\s*$", re.I)
SEPARATOR_RE = re.compile(r"^-{4,}\s*$")


def clean_path(value: str) -> str:
    return re.sub(r"\s+\(0x[0-9a-f]+\)$", "", value, flags=re.I)


def tsv_value(value: str) -> str:
    return value.replace("\t", " ").replace("\r", " ").replace("\n", " ") or "-"


def records(lines: list[str]) -> list[Record]:
    result: list[Record] = []
    current = Record()

    def commit() -> None:
        nonlocal current
        if current.path or current.bundle_id or current.canonical_id or current.name:
            result.append(current)
        current = Record()

    for line in lines:
        if SEPARATOR_RE.match(line):
            commit()
            continue
        match = FIELD_RE.match(line)
        if not match:
            continue
        key, value = match.group(1).casefold(), match.group(2)
        if key in {"bundle id", "identifier"}:
            current.bundle_id = value
        elif key == "canonical id":
            current.canonical_id = value
        elif key == "name":
            current.name = value
        elif key == "path":
            current.path = clean_path(value)
    commit()
    return result


def is_adobe_identity(record: Record) -> bool:
    identifiers = (record.bundle_id, record.canonical_id)
    if any(value.casefold().startswith("com.adobe.") for value in identifiers if value):
        return True
    # A name alone is deliberately insufficient. This fallback is for older
    # records that omit an identifier but still retain an Adobe-named bundle.
    return "adobe" in record.name.casefold() and "adobe" in os.path.basename(record.path).casefold()


def write_scan(output: str, source: list[str]) -> None:
    stale_seen: set[tuple[str, str]] = set()
    live_seen: set[str] = set()
    with open(output, "w", encoding="utf-8") if output != "-" else sys.stdout as stream:
        for record in records(source):
            if not record.path or not record.path.casefold().endswith(".app"):
                continue
            exists = os.path.exists(record.path)
            if exists:
                for identifier in (record.bundle_id, record.canonical_id):
                    if identifier and identifier.casefold() not in live_seen:
                        live_seen.add(identifier.casefold())
                        print("LIVE\t" + identifier.replace("\t", " "), file=stream)
                continue
            if not is_adobe_identity(record):
                continue
            key = (record.bundle_id.casefold() or record.canonical_id.casefold() or record.path.casefold(), record.path)
            if key in stale_seen:
                continue
            stale_seen.add(key)
            values = (record.bundle_id, record.canonical_id, record.name, record.path)
            print("STALE\t" + "\t".join(tsv_value(value) for value in values), file=stream)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="-", help="TSV output path; '-' means stdout")
    args = parser.parse_args()
    write_scan(args.output, sys.stdin.readlines())


if __name__ == "__main__":
    main()
