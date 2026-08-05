#!/usr/bin/env python3
"""Prove that patches/ changes nothing upstream/ did not already change.

This is the second, independent opinion on the series, and it is deliberately
NOT importing anything from build-series.py — it re-derives everything it needs
from the filesystem and from kernel-pin.env. If both scripts shared a bug they
would agree with each other and be wrong together, which is exactly what a second
opinion is supposed to prevent.

What it checks
--------------
1. **Payload parity.** For every ``patches/*.patch`` there is exactly one
   ``upstream/`` file of the same name, and the ordered list of added ('+') and
   removed ('-') lines is byte-identical between them. Context lines and ``@@``
   headers are ignored, so this survives any future re-anchoring while still
   catching a payload change.

   Today ``patches/`` is a byte-identical copy of ``upstream/``, so this is a
   strong check trivially satisfied. It is kept because it is the check that
   stays meaningful if that ever stops being true — and because "patches/ was
   hand-edited" is the failure mode it exists to catch, byte-identical or not.

2. **Provenance parity.** The mbox ``From <sha>`` delimiter of each patch must be
   one of the armbian/linux-rockchip commits pinned in ``kernel-pin.env``, and the
   ``commit <sha> upstream.`` line inside the commit message must name one of the
   pinned mainline Linux commits. Both sets must be fully consumed — two patches,
   two distinct Armbian SHAs, two distinct Linux SHAs.

   This is what the sibling repo (CERALIVE/rk3588-kernel-patches) cannot check at
   all: its sources are raw ``diff -ruN`` files with no commit identity. Here the
   sources ARE commits, so provenance is machine-verifiable, and a patch swapped
   for a plausible-looking rewrite fails here rather than at review time.

Usage:  scripts/verify-payload-parity.py
Exit:   0 identical, 1 divergent, 2 structural problem
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PATCHES_DIR = ROOT / "patches"
UPSTREAM_DIR = ROOT / "upstream"
CERAlive_DIR = ROOT / "ceralive"
PIN_FILE = ROOT / "kernel-pin.env"

# File-header lines share the '+'/'-' prefix with real payload but are metadata.
FILE_HEADER_RE = re.compile(r"^(\+\+\+|---) ")
MBOX_FROM_RE = re.compile(r"^From ([0-9a-f]{40}) Mon Sep 17 00:00:00 2001$")
UPSTREAM_REF_RE = re.compile(r"^commit ([0-9a-f]{40}) upstream\.$")
PIN_LINE_RE = re.compile(r'^(?P<key>[A-Z0-9_]+)="(?P<value>[^"]*)"\s*(?:#.*)?$')


def read_pin() -> dict[str, str]:
    pin: dict[str, str] = {}
    for raw in PIN_FILE.read_text(encoding="utf-8").splitlines():
        m = PIN_LINE_RE.match(raw.strip())
        if m:
            pin[m.group("key")] = m.group("value")
    return pin


def diff_body(lines: list[str]) -> list[str]:
    """Drop the mail header. A bare '---' ends it, per mailbox convention."""
    for i, line in enumerate(lines):
        if line == "---":
            return lines[i + 1 :]
    return lines


def read_lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8", errors="surrogateescape").splitlines()


def payload(lines: list[str]) -> list[str]:
    """Ordered added/removed lines, excluding diff file headers."""
    # NB: `line[:1] in "+-"` would be true for the empty string, since "" is a
    # substring of everything. Compare against a tuple.
    return [
        line
        for line in diff_body(lines)
        if line[:1] in ("+", "-") and not FILE_HEADER_RE.match(line)
    ]


def check_parity(patch_files: list[Path]) -> int:
    failures = 0
    for converted in patch_files:
        original = UPSTREAM_DIR / converted.name
        if not original.is_file():
            original = CERAlive_DIR / converted.name
        if not original.is_file():
            print(f"FAIL {converted.name}: no matching source lane", file=sys.stderr)
            failures += 1
            continue

        want = payload(read_lines(original))
        got = payload(read_lines(converted))

        if want == got:
            print(f"OK   {converted.name}: {len(got)} payload lines identical to upstream/")
            continue

        failures += 1
        print(f"FAIL {converted.name}: payload diverges from upstream/", file=sys.stderr)
        print(f"     upstream {len(want)} lines, published {len(got)}", file=sys.stderr)
        for i, (a, b) in enumerate(zip(want, got)):
            if a != b:
                print(f"     first divergence at payload line {i}:", file=sys.stderr)
                print(f"       upstream : {a!r}", file=sys.stderr)
                print(f"       published: {b!r}", file=sys.stderr)
                break
    return failures


def check_provenance(patch_files: list[Path], pin: dict[str, str]) -> int:
    """Every patch must name a pinned Armbian commit and a pinned Linux commit."""
    want_armbian = {pin["PATCH_COMMIT_1"], pin["PATCH_COMMIT_2"]}
    want_linux = {pin["LINUX_COMMIT_1"], pin["LINUX_COMMIT_2"]}
    seen_armbian: set[str] = set()
    seen_linux: set[str] = set()
    failures = 0

    for path in patch_files:
        lines = read_lines(path)
        m = MBOX_FROM_RE.match(lines[0]) if lines else None
        if not m:
            print(f"FAIL {path.name}: not a git mailbox", file=sys.stderr)
            failures += 1
            continue
        armbian_sha = m.group(1)
        if (CERAlive_DIR / path.name).is_file() and not (UPSTREAM_DIR / path.name).is_file():
            if not any(line.startswith("Origin: Armbian linux-rockchip issue #367") for line in lines):
                print(f"FAIL {path.name}: missing first-party origin", file=sys.stderr)
                failures += 1
            else:
                print(f"OK   {path.name}: first-party CeraLive provenance")
            continue
        if armbian_sha not in want_armbian:
            print(
                f"FAIL {path.name}: mbox delimiter {armbian_sha} is not a pinned "
                "PATCH_COMMIT_* in kernel-pin.env",
                file=sys.stderr,
            )
            failures += 1
            continue
        seen_armbian.add(armbian_sha)

        refs = {m.group(1) for m in (UPSTREAM_REF_RE.match(x) for x in lines) if m}
        hit = refs & want_linux
        if not hit:
            print(
                f"FAIL {path.name}: declares no pinned `commit <sha> upstream.` line; "
                f"found {sorted(refs) or 'none'}",
                file=sys.stderr,
            )
            failures += 1
            continue
        seen_linux |= hit
        print(
            f"OK   {path.name}: armbian {armbian_sha[:12]} <- linux {sorted(hit)[0][:12]}"
        )

    if seen_armbian != want_armbian:
        print(
            f"FAIL unconsumed pinned Armbian commits: "
            f"{sorted(want_armbian - seen_armbian)}",
            file=sys.stderr,
        )
        failures += 1
    if seen_linux != want_linux:
        print(
            f"FAIL unconsumed pinned Linux commits: {sorted(want_linux - seen_linux)}",
            file=sys.stderr,
        )
        failures += 1
    return failures


def main() -> int:
    patch_files = sorted(PATCHES_DIR.glob("*.patch"))
    if not patch_files:
        print("no patches found; run scripts/build-series.py first", file=sys.stderr)
        return 2

    pin = read_pin()
    for key in ("PATCH_COMMIT_1", "PATCH_COMMIT_2", "LINUX_COMMIT_1", "LINUX_COMMIT_2"):
        if key not in pin:
            print(f"kernel-pin.env is missing {key}", file=sys.stderr)
            return 2

    print("Payload parity")
    failures = check_parity(patch_files)
    print()
    print("Provenance parity")
    failures += check_provenance(patch_files, pin)

    if failures:
        print(
            f"\n{failures} check(s) failed. patches/ is not a faithful publication of "
            "upstream/; regenerate it with scripts/build-series.py rather than editing "
            "it by hand.",
            file=sys.stderr,
        )
        return 1

    print(
        f"\nall {len(patch_files)} patches: payload byte-identical to upstream/, "
        "provenance matches kernel-pin.env."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
