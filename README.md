# rk3588-vendor-kernel-patches

Out-of-tree patches for the **Armbian vendor BSP kernel** the shipped CeraLive
image actually runs, packaged as a `git am`-able mailbox series pinned to an
exact commit.

They fix one thing: **HDMI-RX audio capture, which the vendor kernel regressed.**

| | |
|---|---|
| **Target kernel** | `armbian/linux-rockchip` branch `rk-6.1-rkr5.1` @ `95e85f6cb496c75807c5b16f158853578e7e7d1b` |
| **Which package that is** | `linux-image-vendor-rk35xx` **6.1.115** — what the shipped image installs |
| **Why that commit** | Its timestamp matches the board's kernel build stamp to the second — derived in [`docs/PREFLIGHT.md`](docs/PREFLIGHT.md) |
| **Boards** | Radxa Rock 5B+, Orange Pi 5+ (both `BOARDFAMILY=rockchip-rk3588`, both on this kernel) |
| **Patch sources** | `upstream/` from [`armbian/linux-rockchip` PR #487](https://github.com/armbian/linux-rockchip/pull/487), plus the first-party `ceralive/` lane |
| **Status** | Applies cleanly, gate is green. `0001`-`0003` are built and board-tested; end-to-end HDMI audio is still broken and `0004` is the diagnostic patch added to find out why. |

> **Not to be confused with [`CERALIVE/rk3588-kernel-patches`](https://github.com/CERALIVE/rk3588-kernel-patches).**
> That repository is scoped exclusively to the **mainline / `edge` 7.1** kernel
> track. This one is the **vendor 6.1** track. They target different kernels,
> fix different things, and neither one's patches apply to the other's tree.

---

## The bug

On a production CeraLive Rock 5B+ running `6.1.115-vendor-rk35xx`, with a genuine
locked 1920x1080p59.94 HDMI signal on the input:

```
$ cat /proc/asound/pcm
...
03-00: rockchip,hdmiin i2s-hifi-0 :
```

That trailing bare colon is the whole problem — the card exists, the codec binds,
nothing errors, and there are **zero playback and zero capture substreams**. There
is no device to record from. It is a completely silent failure.

### Root cause

`armbian/linux-rockchip` commit
[`78c67d98f221`](https://github.com/armbian/linux-rockchip/commit/78c67d98f221895336d41d8799b38eff6b6b7b4e)
("ASoC: hdmi-codec: disable capture for HDMI-TX to fix mono audio", PR #430,
merged 2025-11-20) added this to `hdmi_codec_probe()`:

```c
	/* Disable capture for HDMI-TX (output only) to prevent
	 * PulseAudio from trying to open capture streams which
	 * causes "Only one simultaneous stream supported!" errors
	 * and results in mono audio output.
	 */
	daidrv[i].capture.channels_min = 0;
	daidrv[i].capture.channels_max = 0;
```

It was aimed at RK3576 NanoPi HDMI **transmit** boards, and it works for them.
But it is unconditional and applies to *every* `hdmi-audio-codec` instance — and
on RK3588, `rk_hdmirx` registers HDMI **receive** through that same codec. So the
fix for TX silently killed RX.

### The fix

Two backports of two real mainline Linux ASoC commits, restoring the upstream
mechanism the vendor tree had diverged from:

| | Patch | Backport of | What it does |
|---|---|---|---|
| `0001` | `ASoC: hdmi-codec: Allow playback and capture to be disabled` | Linux `f77a066f4ed3` (Mark Brown) | Replaces the unconditional zeroing with per-instance `no_i2s_playback` / `no_i2s_capture` / `no_spdif_playback` / `no_spdif_capture` flags. A driver that wants a direction gone asks for it; `rk_hdmirx` asks for nothing, so its capture survives. |
| `0002` | `ASoC: hdmi-codec: only startup/shutdown on supported streams` | Linux `e041a2a55058` (Emil Svendsen, applied by Mark Brown) | Makes `hdmi_codec_startup`/`shutdown` a silent no-op on an unsupported direction instead of erroring, which multi-codec cards need. Companion to `0001`; both are required together. |
| `0003` | `Increase PL330 and HDMI-RX I2S DMA budgets` | CeraLive, from Armbian issue #367 | Raises `MCODE_BUFF_PER_REQ` 256→512 and `MAXBURST_PER_FIFO` 8→16. The issue proposed the exact change; it has no upstream commit counterpart. |
| `0004` | `Instrument the HDMI-RX capture path for the silent EIO` | CeraLive, first-party | **Diagnostic only — changes no behaviour.** Reports the ALSA, dmaengine, i2s-tdm and PL330 conditions that currently turn into an `EIO` on `read()` with no kernel log at all. Expected to be reverted once the root cause is known. |

The first two were backported onto `rk-6.1-rkr5.1` by Stepan Mazurov (`smazurov`)
and submitted as PR #487. `0003` and `0004` are independently authored by CeraLive
from the issue report, board validation, and the sources at the pin. Full
attribution and the licence audit are in
[`docs/PROVENANCE.md`](docs/PROVENANCE.md).

**PR #487 is open, not merged.** This repository exists so CeraLive can carry the
fix now, pinned and gated, without waiting on someone else's merge queue — and
without pretending the PR landed.

---

## Layout

```
upstream/          verbatim `git format-patch` output from the two pinned commits
ceralive/          first-party `git format-patch` output with no upstream commit counterpart
patches/           the git-am series — GENERATED from both lanes, never hand-edit
scripts/           preflight · build-series · verify-payload-parity · apply
kernel-pin.env     every pinned coordinate, in one sourceable file
docs/              provenance audit · preflight derivation
```

---

## Apply the series

Everything below is executed verbatim by CI on every push and pull request, so it
cannot silently rot.

### The short way

```bash
git clone https://github.com/CERALIVE/rk3588-vendor-kernel-patches
cd rk3588-vendor-kernel-patches
scripts/apply.sh
```

That shallow-fetches the pinned BSP commit into `.work/linux`, verifies the
series is generated and payload-identical to its source, checks the regression is
actually present, applies with `git am`, runs post-apply checks, and cleans up.
Roughly 300 MB of fetch and about two minutes. Keep the tree, or bring your own:

```bash
KEEP_TREE=1 scripts/apply.sh                 # keep .work/linux
scripts/apply.sh /path/to/your/linux         # use an existing tree
```

`apply.sh` refuses to touch a tree with uncommitted changes, and refuses to apply
to a tree that does not contain the pinned commit.

### The manual way

```bash
source kernel-pin.env

# rk-6.1-rkr5.1 has no tags and its tip has moved past our pin, so fetch the
# exact commit rather than cloning the branch.
git init linux && cd linux
git remote add origin "$KERNEL_MIRROR"
git fetch --depth 1 origin "$KERNEL_COMMIT"
git checkout FETCH_HEAD

# git am needs an identity
git config user.name  "Your Name"
git config user.email "you@example.com"

git am --keep-non-patch ../patches/*.patch
```

Shell glob order is lexical, which is the correct apply order.
[`patches/series`](patches/series) records it explicitly if you need it.

---

## Use with `armbian-build`

Armbian applies user patches per kernel family. For `vendor` on rk3588 the
directory is `rk35xx-vendor-6.1` — a **top-level** family dir, not one under
`archive/`:

```bash
git clone --depth 1 https://github.com/armbian/build
mkdir -p build/userpatches/kernel/rk35xx-vendor-6.1/
cp patches/*.patch build/userpatches/kernel/rk35xx-vendor-6.1/
cd build && ./compile.sh BOARD=rock-5b-plus BRANCH=vendor
```

Do not copy `patches/series` into that directory — Armbian would try to apply it
as a patch.

> The family directory is derived, not guessed: `KERNELPATCHDIR='rk35xx-vendor-6.1'`
> is set literally by `config/sources/families/rockchip-rk3588.conf`, and user
> patches are read from `${USERPATCHES_PATH}/kernel/${KERNELPATCHDIR}`. See
> [`docs/PREFLIGHT.md`](docs/PREFLIGHT.md).

**Caveat worth stating plainly:** Armbian would build the branch *tip*, not our
pinned commit. The series applies to the pin; whether it applies to whatever the
tip is on the day you run that is exactly what `scripts/apply.sh` exists to
answer, and it answers it for the pin only.

---

## Changing the pin

`kernel-pin.env` is the single source of truth. Bumping it is a deliberate act:

```bash
scripts/preflight.sh --head     # has Armbian moved the vendor branch? did PR #487 merge?
# edit KERNEL_COMMIT / KERNEL_COMMIT_DATE / KERNEL_COMMIT_SUBJECT / KERNEL_VERSION together
scripts/apply.sh                # the gate must stay green
```

**If PR #487 merges, do not bump — retire.** A pin taken after the merge already
carries the fix, `apply.sh`'s pre-apply check will report the regression absent,
and applying on top would fail. That is the intended end state of this
repository, not a malfunction. `preflight.sh` watches for it.

**If the series ever stops applying**, do not hand-edit `patches/` and do not
invent a resolution. Either re-export from `armbian/linux-rockchip` at the pinned
SHAs, or re-pin deliberately and re-run the gate.

---

## Differences from the mainline sibling repo

[`CERALIVE/rk3588-kernel-patches`](https://github.com/CERALIVE/rk3588-kernel-patches)
is the structural template for this repository, and most of its discipline is
carried over unchanged: one sourceable pin file, a generated `patches/` that CI
proves is generated, an independent payload-parity checker, a preflight that
re-derives the Armbian mapping from source, and an `apply.sh` that is both the
documented human command and the CI gate.

Three things are genuinely different, and each simplification is because the
underlying situation is genuinely simpler — not because rigour was dropped:

**1. Both source lanes are already `git am`-able, so there is nothing to convert.** The
sibling's whole reason for existing is that its upstream ships raw
`diff -ruN aa/ bb/` output with no mail headers, so `git am` rejects it before
reading a hunk — its `build-series.py` has to synthesise a mailbox around every
file. Here both lanes are `git format-patch` output with real authors, dates,
subjects, commit messages, and `diff --git` bodies. `git am` takes them as-is.
So `patches/` is a **byte-identical copy** of `upstream/` and `ceralive/` plus a
generated `series` file. `build-series.py` validates rather than converts: the
imported lane is checked against pinned Armbian and mainline SHAs, while the
first-party lane is checked against its issue origin.

**2. There is no `rebase/` mechanism, deliberately.** The sibling pins a *tag* on
a rolling stable branch, targets a kernel its upstream never tested against, and
therefore needs context re-anchoring plus a machine-enforced "context lines only"
rule to keep re-anchoring honest. This repository pins one immutable *commit* and
the series applies to it with no re-anchoring whatsoever — proven by the gate, not
assumed. A re-anchor engine with nothing to re-anchor would be complexity
pretending to be rigour. If a future bump genuinely drifts, add it then, with a
real conflict to point at.

**3. The licence question is smaller.** The sibling carries ~4,200 lines of ported
vendor driver code under a `(GPL-2.0+ OR MIT)` disjunction from a repository with
no `LICENSE` file, which forces a long caveat about the MIT branch. Here both
source repositories ship the kernel's own `COPYING`, both modified files are plain
`GPL-2.0-only`, no new file is added, and no SPDX line is touched. There is no MIT
branch to elect and no caveat to write.

One thing this repository has that the sibling does not: **the patch source is an
unmerged pull request.** That risk is real, and it is contained by pinning commit
SHAs rather than `refs/pull/487/head` — a SHA cannot be made to name different
content. [`docs/PROVENANCE.md`](docs/PROVENANCE.md) §3 covers it in full.

---

## Scope — what this repository does not do

It gates **patch application**. It does not:

- build a kernel, or produce any `.deb` or image artifact;
- verify the patched tree compiles;
- repeat the completed board validation; it records the PL330 rejection fix, not
  end-to-end audio;
- touch a board, an image, or `image-building-pipeline`'s build stages;
- claim PR #487 is merged. **It is open.**

Kernel builds are the image pipeline's job. The board evidence for `0003` is
recorded in `vendor-kernel-hdmi-audio-bench-boot-proof-2.md` in the CeraLive
validation evidence set.

**Where end-to-end audio actually stands.** `0001`-`0003` restored the capture
capability and that half is board-confirmed: `/dev/snd/pcmC3D0c` exists, opens,
and negotiates `hw_params`. With a second, EDID-confirmed audio-capable HDMI
source attached, every `read()` still fails with `EIO` and produces a 44-byte
header-only WAV, and `dmesg` — cleared immediately beforehand — stays completely
empty. The earlier "the test source reported no embedded audio" caveat is
therefore no longer the explanation; the sample-transfer path is broken for a
reason nobody has yet seen. `0004` exists solely to make that reason printable.
It is diagnostic instrumentation, not a fix, and no further guess at burst or
buffer sizes should be made before its output has been read off a board.

---

## Licence and provenance

Read [`docs/PROVENANCE.md`](docs/PROVENANCE.md) before depending on this.

Short version: `0001` and `0002` modify only `sound/soc/codecs/hdmi-codec.c` and
`include/sound/hdmi-codec.h`, both of which carry
`SPDX-License-Identifier: GPL-2.0-only` (read from the files at the pinned
commit). No new file is added, no SPDX line is altered, no `MODULE_LICENSE` is
touched, and nothing under `include/uapi/` is involved. This is GPL-2.0-only
kernel code modified by GPL-2.0-only kernel patches, redistributed as GPL-2.0-only
kernel patches. No legal review has been performed and none is implied.

`docs/PROVENANCE.md` §5 additionally records a finding neither commit message
mentions: `0001` is a **partial** backport of upstream `f77a066f`, omitting its
DAPM null-route guard. That is currently unreachable — no driver in the tree sets
any of the four flags — and `scripts/apply.sh` asserts the pair so it cannot
become reachable silently.

## Credits

`0001` is the work of **Mark Brown** `<broonie@kernel.org>`, upstream ASoC
maintainer. `0002` is the work of **Emil Abildgaard Svendsen**
`<emas@bang-olufsen.dk>` of Bang & Olufsen, applied upstream by Mark Brown.
Both were backported to the Armbian vendor BSP by **Stepan Mazurov**
(`smazurov`), who also tested them and opened PR #487. The files they modify are
copyright **Texas Instruments Incorporated**, authored by **Jyri Sarha**.

CeraLive contributes packaging, pinning, auditing and CI, and authors `0003` and
`0004` in the separate `ceralive/` lane. It is not claimed to be upstream-mergeable.
