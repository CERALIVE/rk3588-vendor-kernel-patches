# rk3588-vendor-kernel-patches

> ## Preserved, not retired — and open for contributions
>
> **This patch series is no longer consumed by CeraLive's image-building pipeline.**
> The shipped CeraLive image runs the mainline / Armbian `edge` 7.2 kernel, whose patch
> series lives in the sibling repository
> [`CERALIVE/rk3588-kernel-patches`](https://github.com/CERALIVE/rk3588-kernel-patches).
> The project owner confirmed that track as the permanent production kernel after
> hands-on testing on the bench devices.
>
> **This repository is deliberately preserved, and it stays fully active.** It is not
> archived, not frozen, and not read-only. What it carries is a documented,
> board-confirmed repair for a real upstream regression on the Armbian vendor 6.1 BSP
> kernel — and those fixes remain valuable to anyone building their own custom
> vendor-kernel images. CeraLive moving its own production images to the mainline track
> does not make the vendor track any less broken for the people still building on it.
>
> **Contributions and pull requests remain welcome here.** Issues, patch improvements,
> pin bumps, and board reports are all still accepted.
>
> Background: the CeraLive workspace plan `cerastream-glibc-pipewire-network-ui`.

Out-of-tree patches for the **Armbian vendor BSP kernel**
(`linux-image-vendor-rk35xx` 6.1.115), packaged as a `git am`-able mailbox series
pinned to an exact commit.

They fix one thing: **HDMI-RX audio capture, which the vendor kernel regressed.**

| | |
|---|---|
| **Target kernel** | `armbian/linux-rockchip` branch `rk-6.1-rkr5.1` @ `95e85f6cb496c75807c5b16f158853578e7e7d1b` |
| **Which package that is** | `linux-image-vendor-rk35xx` **6.1.115** — the Armbian vendor BSP kernel package. CeraLive images shipped it until the move to the mainline `edge` 7.2 track; anyone still building vendor-kernel images installs it |
| **Why that commit** | Its timestamp matches the board's kernel build stamp to the second — derived in [`docs/PREFLIGHT.md`](docs/PREFLIGHT.md) |
| **Boards** | Radxa Rock 5B+, Orange Pi 5+ (both `BOARDFAMILY=rockchip-rk3588`) |
| **Patch sources** | `upstream/` from [`armbian/linux-rockchip` PR #487](https://github.com/armbian/linux-rockchip/pull/487), plus the first-party `ceralive/` lane |
| **Status** | Applies cleanly, gate is green. `0001`-`0003` are built and board-tested; `0004` is retained as diagnostic instrumentation; and `0005` is board-confirmed on one Radxa ROCK 5B+ test with the evidence recorded below. |

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
| `0004` | `Instrument the HDMI-RX capture path for the silent EIO` | CeraLive, first-party | **Diagnostic only — changes no behaviour.** Reports the ALSA, dmaengine, i2s-tdm and PL330 conditions that turned into an `EIO` on `read()` with no kernel log at all. Retained as regression instrumentation for `0005` and future board checks. |
| `0005` | `Start the HDMI-RX audio domain from the capture lifecycle` | CeraLive, first-party | **The fix.** `rk_hdmirx` gates its audio output behind `GLOBAL_SWENABLE.AUDIO_ENABLE` and `AUDIO_PROC_CONFIG0.I2S_EN`, both of which are only ever set by `hdmirx_delayed_work_audio()` — and nothing in the ALSA capture path started that work. Opening the PCM now starts it — waiting on a completion the work signals before it calls back into hdmi-codec, never on the work item itself (see "The bug" for the deadlock the first version of this patch had), and with a gated synchronous cancel on every teardown path. |

The first two were backported onto `rk-6.1-rkr5.1` by Stepan Mazurov (`smazurov`)
and submitted as PR #487. `0003`, `0004` and `0005` are independently authored by CeraLive
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

**If PR #487 merges, do not bump — the patches become superseded.** A pin taken
after the merge already carries the fix, `apply.sh`'s pre-apply check will report
the regression absent, and applying on top would fail. Stop tracking new commits,
but keep this repository and its content available as useful historical reference.
`preflight.sh` watches for it.

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
- independently repeat board validation; it records the completed end-to-end
  audio validation for `0005`, not a claim of broader hardware coverage;
- touch a board, an image, or `image-building-pipeline`'s build stages;
- claim PR #487 is merged. **It is open.**

Kernel builds are the image pipeline's job. The board evidence for `0003` is
recorded in `vendor-kernel-hdmi-audio-bench-boot-proof-2.md` in the CeraLive
validation evidence set.

**Earlier failure before `0005`.** `0001`-`0003` restored the capture capability
and that half was board-confirmed: `/dev/snd/pcmC3D0c` existed, opened, and
negotiated `hw_params`. Before `0005`, every `read()` then failed with `EIO`, silently.
`0004` made that failure printable, and its board output named the fault:

```
capture dma on: DMACR=0x10f0010 XFER=0x0 INTSR=0x0 RXFIFOLR=0x0
capture transfer timed out (DMA or IRQ trouble?): state=3 hw_ptr=0 appl_ptr=0
capture xfer failed: err=-5 state=3 hw_ptr=0 appl_ptr=0
```

The DMA request line is armed and `hw_ptr` never moves, so nothing reaches the
FIFO. That is **not** an I2S-side fault — `rockchip_i2s_tdm_xfer_start()` does
write `I2S_XFER_RXS_START` for a non-TRCM capture stream, and the `XFER=0x0`
above is read inside `rockchip_i2s_tdm_dma_ctrl()`, i.e. *before* that write, out
of the regmap cache (`I2S_XFER` is non-volatile and absent from `reg_defaults`
under `REGCACHE_FLAT`). It never said the RX enable bit was unset.

The bus feeding the receiver is idle. `rk_hdmirx` gates its audio output behind
`GLOBAL_SWENABLE.AUDIO_ENABLE` and `AUDIO_PROC_CONFIG0.I2S_EN`;
`hdmirx_audio_setup()` explicitly clears the first and never sets the second, and
both are only ever set from `hdmirx_delayed_work_audio()`. That work's only
in-kernel trigger is `avpunit_1_int_handler()`'s one-shot
`DEFRAMER_VSYNC_THR_REACHED_IRQ`, which masks its own source off after the first
delivery; its only other trigger is the vendor `RK_HDMIRX_CMD_SET_AUDIO_STATE`
V4L2 private ioctl, which no ALSA client issues. So opening the capture PCM left
the HDMI-RX audio domain off, and the controller drove no BCLK, LRCK or SDATA at
all. `0005` connects the two lifecycles.

**`0005` was corrected on 2026-08-06 after a concurrency review, before any board
test.** Its first version waited for the audio work with `flush_delayed_work()`
from inside `hdmirx_audio_startup()` — which `hdmi_codec_startup()` calls with
`hcp->lock` held, while the work's success path calls `plugged_cb()`, which takes
that same `hcp->lock`. That is a hard deadlock, and it fires only on the path
where the fix *works*. The current version waits on a `struct completion` that
the work signals **before** the lock-taking callback, so the waiter never needs
the worker to finish; it also replaces the non-synchronous
`cancel_delayed_work()` on the teardown paths with a gated
`cancel_delayed_work_sync()`, so a capture open racing an unplug cannot re-arm
work behind the teardown. See the patch's own commit message for the full trace.

`0005` is board-confirmed on one Radxa ROCK 5B+ test using image
`20260806T223730Z.raw` after a clean full `dd` reflash. CeraUI's live **Audio
levels** meters showed real, non-frozen fluctuating values across repeated
samples: Channel 1 approximately 52–55/100 and Channel 2 approximately
53–55/100. Kernel dmesg reported `capture started: XFER=0x2 (cached; RXS=1)`
with non-zero `RXFIFOLR=0xa`, with zero `capture xfer failed` lines. ALSA
ground truth from `/proc/asound/card3/pcm0c/sub0/status` showed `hw_ptr`
advancing `15934388 → 16030718` over approximately `2.007s` (approximately
48000 Hz, matching the driver's reported `restart audio fs(44100 -> 48000)`
capture rate), while `appl_ptr` tracked closely with bounded delay (`176 → 368`)
and no runaway drift. The capture owner was cerastream's own idle audio-meter
sidecar (pid 2907), so this was verified through the real production consumer,
not a one-off manual `arecord`.

This confirms the gate for that board and source test only; it does not claim
coverage of other boards, source formats or resolutions, or unplug/replug audio
recovery. Keep the permanent regression criteria: a board must show `hw_ptr`
advancing, `RXS=1` with a non-zero `RXFIFOLR`, and no `capture xfer failed` line
at all.

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

CeraLive contributes packaging, pinning, auditing and CI, and authors `0003`,
`0004` and `0005` in the separate `ceralive/` lane. It is not claimed to be upstream-mergeable.
