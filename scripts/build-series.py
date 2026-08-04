#!/usr/bin/env python3
"""Validate the imported mailboxes and publish them as the git-am series.

Why this is SHORTER than its sibling repo's converter
-----------------------------------------------------
``CERALIVE/rk3588-kernel-patches`` imports raw ``diff -ruN`` output with no mail
headers at all, so its ``build-series.py`` has to synthesise a mailbox around
each file before ``git am`` will look at it.

This repository has no such problem, and the honest thing to do is say so rather
than invent one. ``upstream/`` here is ``git format-patch`` output taken from real
commits in a real clone of ``armbian/linux-rockchip``. Each file already carries
its ``From <sha> Mon Sep 17 00:00:00 2001`` delimiter, a real author, a real date,
a real ``Subject:``, the full backport commit message, and a proper ``diff --git``
body. ``git am`` accepts them as-is. So ``patches/`` is a **byte-identical copy**
of ``upstream/`` plus a generated ``series`` file, and this script's real job is
validation, not conversion.

What it still buys us, and why it is worth keeping
--------------------------------------------------
The sibling's discipline — ``patches/`` is generated, never hand-edited, and CI
proves it — is the part that matters, and it is preserved exactly:

* ``--check`` regenerates into a temp directory and byte-compares, so a
  hand-edited ``patches/`` is a red build.
* Every ``upstream/`` file is structurally validated before it is published: the
  mbox delimiter must carry the exact commit SHA pinned in ``kernel-pin.env``,
  the author must match, the ordinal must match, the backport must declare the
  mainline Linux commit it came from, and the body must contain a real
  ``diff --git`` hunk.

That last group is the check the sibling cannot make, because its sources are not
commits. Here it means a swapped, truncated, or re-authored patch file fails in
seconds rather than at ``git am`` time — or worse, silently.

What is deliberately ABSENT
---------------------------
There is no ``rebase/<tag>.rules`` mechanism and no context re-anchoring. The
sibling needs one because it pins a *tag* on a rolling stable branch and its
upstream targeted a different kernel entirely. This repository pins one immutable
*commit*, and the series applies to it cleanly with no re-anchoring at all. A
re-anchor engine with nothing to re-anchor would be complexity pretending to be
rigour. If a future pin bump ever does drift, add the mechanism then — with a
real conflict to point at.

Usage
-----
    scripts/build-series.py            regenerate patches/
    scripts/build-series.py --check    rebuild into a temp dir and diff; non-zero
                                       exit if patches/ is stale or hand-edited
"""

from __future__ import annotations

import argparse
import filecmp
import re
import shutil
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UPSTREAM_DIR = ROOT / "upstream"
PATCHES_DIR = ROOT / "patches"
PIN_FILE = ROOT / "kernel-pin.env"

SERIES_TOTAL = 2

MBOX_FROM_RE = re.compile(r"^From ([0-9a-f]{40}) Mon Sep 17 00:00:00 2001$")
SUBJECT_RE = re.compile(r"^Subject: \[PATCH (\d+)/(\d+)\] ")
UPSTREAM_REF_RE = re.compile(r"^commit ([0-9a-f]{40}) upstream\.$")


class SeriesError(RuntimeError):
    """A source file is not what kernel-pin.env says it is. Never papered over."""


@dataclass(frozen=True)
class Patch:
    """One member of the series."""

    filename: str
    ordinal: int
    commit_key: str  # kernel-pin.env key holding the armbian/linux-rockchip SHA
    linux_commit_key: str  # kernel-pin.env key holding the mainline Linux SHA
    author: str
    summary: str


SERIES: tuple[Patch, ...] = (
    Patch(
        filename="0001-ASoC-hdmi-codec-Allow-playback-and-capture-to-be-dis.patch",
        ordinal=1,
        commit_key="PATCH_COMMIT_1",
        linux_commit_key="LINUX_COMMIT_1",
        author="Mark Brown <broonie@kernel.org>",
        summary=(
            "restores the per-instance no_i2s_playback / no_i2s_capture / "
            "no_spdif_playback / no_spdif_capture flags and removes the "
            "unconditional capture zeroing added by the regression commit"
        ),
    ),
    Patch(
        filename="0002-ASoC-hdmi-codec-only-startup-shutdown-on-supported-s.patch",
        ordinal=2,
        commit_key="PATCH_COMMIT_2",
        linux_commit_key="LINUX_COMMIT_2",
        author="Emil Abildgaard Svendsen <EMAS@bang-olufsen.dk>",
        summary=(
            "makes hdmi_codec_startup/shutdown a silent no-op on an unsupported "
            "direction instead of erroring, which multi-codec cards need"
        ),
    ),
)


PIN_LINE_RE = re.compile(r'^(?P<key>[A-Z0-9_]+)="(?P<value>[^"]*)"\s*(?:#.*)?$')


def read_pin() -> dict[str, str]:
    """Parse the shell-ish kernel-pin.env into a plain dict.

    Every assignment in that file is `KEY="value"`, optionally followed by a
    trailing `# comment`. Anything else is a comment or blank and is skipped.
    """
    pin: dict[str, str] = {}
    for raw in PIN_FILE.read_text(encoding="utf-8").splitlines():
        m = PIN_LINE_RE.match(raw.strip())
        if m:
            pin[m.group("key")] = m.group("value")
    return pin


def validate(patch: Patch, pin: dict[str, str]) -> None:
    """Assert an upstream/ file really is the commit kernel-pin.env pins."""
    src = UPSTREAM_DIR / patch.filename
    if not src.is_file():
        raise SeriesError(f"missing upstream mailbox: {src}")

    lines = src.read_text(encoding="utf-8", errors="surrogateescape").splitlines()
    if not lines:
        raise SeriesError(f"{patch.filename}: empty file")

    want_commit = pin[patch.commit_key]
    m = MBOX_FROM_RE.match(lines[0])
    if not m:
        raise SeriesError(
            f"{patch.filename}: first line is not a git mailbox delimiter. "
            "upstream/ must be verbatim `git format-patch` output."
        )
    if m.group(1) != want_commit:
        raise SeriesError(
            f"{patch.filename}: mbox delimiter names {m.group(1)}, but "
            f"kernel-pin.env {patch.commit_key} pins {want_commit}. "
            "A patch file was swapped or re-exported from a different commit."
        )

    if f"From: {patch.author}" not in lines[:5]:
        raise SeriesError(
            f"{patch.filename}: expected `From: {patch.author}` in the mail header"
        )

    subjects = [line for line in lines[:8] if SUBJECT_RE.match(line)]
    if not subjects:
        raise SeriesError(f"{patch.filename}: no `Subject: [PATCH n/m]` header")
    got_ordinal, got_total = SUBJECT_RE.match(subjects[0]).groups()  # type: ignore[union-attr]
    if (int(got_ordinal), int(got_total)) != (patch.ordinal, SERIES_TOTAL):
        raise SeriesError(
            f"{patch.filename}: Subject says [PATCH {got_ordinal}/{got_total}], "
            f"expected [PATCH {patch.ordinal}/{SERIES_TOTAL}]"
        )

    want_linux = pin[patch.linux_commit_key]
    refs = [
        m.group(1) for m in (UPSTREAM_REF_RE.match(line) for line in lines) if m
    ]
    if want_linux not in refs:
        raise SeriesError(
            f"{patch.filename}: does not declare `commit {want_linux} upstream.`. "
            "Every patch here must be a backport of a named mainline Linux commit."
        )

    try:
        sep = lines.index("---")
    except ValueError as exc:
        raise SeriesError(f"{patch.filename}: no `---` mail/body separator") from exc
    if not any(line.startswith("diff --git ") for line in lines[sep:]):
        raise SeriesError(f"{patch.filename}: no `diff --git` body after `---`")


def write_series(out_dir: Path, pin: dict[str, str]) -> None:
    for patch in SERIES:
        validate(patch, pin)

    out_dir.mkdir(parents=True, exist_ok=True)
    for stale in out_dir.glob("*.patch"):
        stale.unlink()
    (out_dir / "series").unlink(missing_ok=True)

    for patch in SERIES:
        # Byte-identical copy, on purpose: the source is already a valid mailbox,
        # so there is nothing to convert and nothing to be gained by rewriting it.
        shutil.copyfile(UPSTREAM_DIR / patch.filename, out_dir / patch.filename)

    series_lines = [
        "# git-am order for the CeraLive RK3588 VENDOR-kernel series.",
        "# Both files are byte-identical copies of upstream/, which is verbatim",
        "# `git format-patch` output from armbian/linux-rockchip PR #"
        + pin["UPSTREAM_PATCHES_PR"]
        + " (OPEN, not merged).",
        f"# Target kernel: {pin['KERNEL_BRANCH']} @ {pin['KERNEL_COMMIT']}",
        f"# Package: {pin['KERNEL_DEB_PACKAGE']} {pin['KERNEL_VERSION']}",
        *(p.filename for p in SERIES),
    ]
    (out_dir / "series").write_text("\n".join(series_lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Publish upstream/ as patches/.")
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify patches/ matches what this script would generate",
    )
    args = parser.parse_args()

    pin = read_pin()

    if not args.check:
        write_series(PATCHES_DIR, pin)
        print(f"wrote {len(SERIES)} patches + series to {PATCHES_DIR}")
        return 0

    with tempfile.TemporaryDirectory() as tmp:
        expected = Path(tmp) / "patches"
        write_series(expected, pin)

        names = sorted({p.name for p in expected.iterdir()})
        match, mismatch, errors = filecmp.cmpfiles(
            PATCHES_DIR, expected, names, shallow=False
        )
        if mismatch or errors:
            print("patches/ is STALE or hand-edited.", file=sys.stderr)
            for name in sorted(mismatch):
                print(f"  differs: {name}", file=sys.stderr)
            for name in sorted(errors):
                print(f"  missing: {name}", file=sys.stderr)
            print("Re-run scripts/build-series.py.", file=sys.stderr)
            return 1

        extra = sorted({p.name for p in PATCHES_DIR.iterdir()} - set(names))
        if extra:
            print(f"unexpected files in patches/: {extra}", file=sys.stderr)
            return 1

        print(f"patches/ is in sync ({len(match)} files).")
        return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SeriesError as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(2)
