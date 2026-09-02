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

## ROLE IN THE GROUP

Holds the **vendor-track RK3588 kernel patch series** for CeraLive: two backports
that restore HDMI-RX audio capture on the Armbian vendor BSP kernel
(`rk-6.1-rkr5.1`, `linux-image-vendor-rk35xx` 6.1.115) — plus two first-party
patches: a DMA-budget fix, a diagnostic instrumentation patch, and the
first-party fix it led to.

Produces **patch text only** — no `.deb`, no kernel, no image artifact. It is
therefore **NOT in the device image `REPOS` array** and has **no `versions.yaml`
pin**, for the same reason `ceralive-infra` has none: there is nothing for the
image pipeline to fetch.

Relates to:
- `image-building-pipeline/` — **not a consumer.** CeraLive's pipeline builds the
  mainline `edge` 7.2 kernel and never sourced `kernel-pin.env`. A third party
  building their own vendor-kernel images is the audience for that file.
- `cerastream/` — the consumer of the capability this restores. On a vendor 6.1
  BSP kernel, HDMI-RX embedded audio is unreachable without this series.
- `CERALIVE/rk3588-kernel-patches` — the **sibling, not the parent**. See below.

Patch source: [`armbian/linux-rockchip` PR #487](https://github.com/armbian/linux-rockchip/pull/487),
**OPEN, not merged**, pinned by commit SHA. `0003` (DMA budgets, from Armbian
issue #367), `0004` (diagnostic instrumentation) and `0005` (the HDMI-RX
audio-domain fix) are first-party CeraLive work
and therefore belong in `ceralive/`, not `upstream/`.

## THIS REPO vs `rk3588-kernel-patches` — READ THIS FIRST

Two patch packages, two kernels, no overlap. Getting this wrong wastes a day.

| | `rk3588-kernel-patches` | **this repo** |
|---|---|---|
| Kernel track | mainline / Armbian `edge` | Armbian `vendor` BSP |
| Kernel | `v7.1.5` (a tag on `linux-7.1.y`) | `rk-6.1-rkr5.1` @ `95e85f6c` (a commit; branch has no tags) |
| Package | none shipped | `linux-image-vendor-rk35xx` 6.1.115 |
| Contents | VEPU580 encoder + 3 HDMI-RX fixes + first-party DT sound card | 2 ASoC hdmi-codec backports + 2 first-party patches |
| Source shape | raw `diff -ruN`, no mail headers | `git format-patch` mailboxes |
| Needs a rebase engine? | yes (moving tag, different base kernel) | **no** (fixed commit, applies clean) |
| Licence shape | `(GPL-2.0+ OR MIT)` disjunction + MIT caveat | plain `GPL-2.0-only`, no caveat |

**Neither one's patches apply to the other's tree**, and neither should grow the
other's content. The mainline repo's own `AGENTS.md` says of the `78c67d98f221`
regression: "There is nothing to fix here … Do not add one." This repository is
where that vendor-side fix lives instead.

## STRUCTURE

```
rk3588-vendor-kernel-patches/
├── kernel-pin.env             # SINGLE SOURCE OF TRUTH for every pinned coordinate
├── upstream/                  # verbatim `git format-patch` output, 2 imported commits
├── ceralive/                  # first-party `git format-patch` output, no upstream counterpart
├── patches/                   # GENERATED git-am series + series file — NEVER hand-edit
├── scripts/
│   ├── preflight.sh           # re-resolve the Armbian vendor mapping; --head for live check
│   ├── build-series.py        # validates upstream/ then publishes it as patches/; --check
│   ├── verify-payload-parity.py  # independent: payload + provenance parity
│   └── apply.sh               # the gate: verify -> fetch pinned commit -> git am -> assert
├── docs/
│   ├── PROVENANCE.md          # licence/attribution audit + the unmerged-PR risk + §5 finding
│   └── PREFLIGHT.md           # how the vendor -> rk-6.1-rkr5.1 mapping was derived
└── .github/workflows/patch-apply.yml
```

## WHERE TO LOOK

| Task | Location |
|------|----------|
| Change the target kernel commit | [`kernel-pin.env`](kernel-pin.env) — then re-run the gate |
| Why THIS commit and not the branch tip | [`docs/PREFLIGHT.md`](docs/PREFLIGHT.md) → "Why a COMMIT is pinned" |
| Whether PR #487 merged yet | `scripts/preflight.sh` (also weekly in CI) |
| Attribution / licence facts | [`docs/PROVENANCE.md`](docs/PROVENANCE.md) |
| The partial-backport hazard | [`docs/PROVENANCE.md`](docs/PROVENANCE.md) §5 |
| Apply the series | `scripts/apply.sh` — see [`README.md`](README.md) |
| What the bug actually looks like on a board | [`README.md`](README.md) → "The bug" |
| Why this is simpler than the sibling repo | [`README.md`](README.md) → "Differences from the mainline sibling repo" |

## KEY FACTS

**The bug is board-confirmed, not theoretical.** On the production Rock 5B+
running `6.1.115-vendor-rk35xx`, with a locked 1920x1080p59.94 input,
`/proc/asound/pcm` shows `03-00: rockchip,hdmiin i2s-hifi-0 :` — a bare trailing
colon, zero playback and zero capture substreams. The codec binds, nothing
errors, and there is simply no device to record from. That silence is why
`apply.sh` asserts the mechanism rather than trusting a green `git am`.

**`patches/` is generated. Editing it by hand is a bug, and CI catches it.**
`scripts/build-series.py --check` regenerates from `upstream/` into a temp dir and
byte-compares. Change `upstream/`, then regenerate — never the other way round.

**`patches/` is a BYTE-IDENTICAL copy of each source lane, and that is correct here.**
Do not "fix" this by adding a conversion step. The sibling repo needs one because
its sources are raw `diff -ruN` files with no mail headers; both lanes here are
`git format-patch` output and `git am` accepts them unchanged.
`build-series.py` is therefore a **validator plus publisher**, not a converter —
and it checks *more* than the sibling's converter can, because commit provenance
is machine-verifiable when the source is a commit: mbox delimiter must be a pinned
`PATCH_COMMIT_*`, body must declare a pinned `LINUX_COMMIT_*`, author and ordinal
must match. A swapped or re-authored patch file fails in seconds.

**There is deliberately NO `rebase/` mechanism.** The sibling needs context
re-anchoring because it pins a moving tag against a kernel its upstream never
targeted. This repo pins one immutable commit and the series applies with zero
re-anchoring — proven by the gate. Adding a re-anchor engine with nothing to
re-anchor would be complexity cosplaying as rigour. If a future pin bump really
drifts, add it then, with a real conflict to point at.

**This repo pins a COMMIT; Armbian tracks a BRANCH — and the branch has no tags.**
`rk-6.1-rkr5.1` moves with every BSP push and publishes no tags, so there is no
tag to pin. `KERNEL_COMMIT=95e85f6cb496c75807c5b16f158853578e7e7d1b` was chosen
because its commit timestamp (`2026-06-14T17:47:08Z`) matches the running board's
kernel build stamp (`Sun Jun 14 17:47:08 UTC 2026`) to the second, and its
`Makefile` reads 6.1.115. **Downstream consumers must pin the same commit.**

**`rk-6.1-rkr5.1` and `rk-6.1-rkr6.1` are DIFFERENT branches, not aliases.**
`rkr6.1` was introduced later (`armbian/build` PR #8719, 2025-10-05) and produces
6.1.118, not our 6.1.115. Everything here is `rkr5.1`; `preflight.sh` asserts the
resolved `KERNELBRANCH` does not contain `rkr6.1`. Note the sibling repo's
`AGENTS.md` names `rkr6.1` when describing this regression — the regression is
real on both branches (`78c67d98` merged to `rkr5.1` via PR #430), but `rkr5.1`
is what CeraLive ships.

**The patch source is an OPEN pull request, and the pin is what contains that
risk.** PR #487 has not merged. A PR ref (`refs/pull/487/head`) is a moving
target — a force-push silently changes what it resolves to. This repository pins
the two **commit SHAs**, which cannot be made to name different content, and
`verify-payload-parity.py` re-asserts that mapping on every run. What the pin does
*not* cover is the PR's fate, so `preflight.sh` re-reads its state and fails on
any change away from `open`.

**If PR #487 merges, RETIRE this repo — do not bump the pin.** A base commit taken
after the merge already carries the fix; `apply.sh`'s pre-apply check will report
the regression absent and the series will not apply. That is the intended end
state, not a malfunction.

**`0001` is a PARTIAL backport, and the gate knows it.** Upstream `f77a066f` also
rewrote `hdmi_codec_dai_probe()`'s DAPM route registration to skip NULL routes,
because zeroing a direction NULLs its `stream_name`. PR #487 did not carry that
hunk. It is currently **unreachable** — `rk_hdmirx` sets no `no_*` flag and a
tree-wide grep finds no driver that does — but the flags exist so a driver *can*
opt in, and `0001`'s own commit message invites exactly that for the RK3576
HDMI-TX case. `apply.sh` fails if the guard is absent **and** any driver opts in.
Details in [`docs/PROVENANCE.md`](docs/PROVENANCE.md) §5. Do not "fix" this by
editing patch content; carry the missing hunk as a third patch with its own
provenance, or push it into PR #487.

**Scope is patch application and provenance.** No kernel is built by this repo and
kernel builds belong to `image-building-pipeline`. `0003` has already been built
and boot-tested on a Rock 5B+; the evidence proves the PL330 descriptor rejection
is gone. Before `0005`, end-to-end HDMI audio remained broken; the board evidence
below confirms the `0005` fix for the tested source.

**`0004` is DIAGNOSTIC ONLY, and is RETAINED on purpose.** It changes no
behaviour, and it is no longer "expected to be reverted": it is the regression
instrumentation used to verify `0005` on a board and remains available for future
regressions. With `0001`-`0003` applied the capture PCM registers, opens and
negotiates `hw_params`, but every `read()` returns `EIO` and `dmesg` — cleared
immediately beforehand — stays empty, including against an EDID-confirmed
audio-capable source. That silence is structural, not incidental: the only `-EIO`
on the rw transfer path is `wait_for_avail()`'s timeout, reported at `pcm_dbg()`
level; `snd_dmaengine_pcm_pointer()` discards its `dmaengine_tx_status()` return
and silently reports position 0; the i2s-tdm interrupt that reports RX overrun is
`platform_get_irq_optional()` and its absence is unlogged; and a PL330 channel
fault is reported at `dev_info()` level. `0004` makes each of those printable.
Do not treat it as a fix.

**`0005` IS the fix, and it is not on the I2S side.** `0004`'s board output showed
`DMACR` armed and `hw_ptr` stuck at 0, with `XFER=0x0` — but that `XFER` is read
inside `rockchip_i2s_tdm_dma_ctrl()`, which runs *before*
`rockchip_i2s_tdm_xfer_start()`, and `I2S_XFER` is non-volatile and absent from
`reg_defaults` under `REGCACHE_FLAT`, so the read returned the regmap cache and
not the register. It never proved the RX enable bit was unset, and reading it as
a smoking gun is a mistake — `0005` adds a post-start read-back next to it so the
next board run cannot repeat that misreading.

The real gap is that `rk_hdmirx` gates its audio output behind
`GLOBAL_SWENABLE.AUDIO_ENABLE` and `AUDIO_PROC_CONFIG0.I2S_EN`, both of which are
set **only** by `hdmirx_delayed_work_audio()`, whose only in-kernel trigger is a
one-shot `DEFRAMER_VSYNC_THR_REACHED_IRQ` that masks its own source off after the
first delivery. Nothing in `startup`/`hw_params`/`trigger` ever started it, so the
controller drove no clocks and the receiver clocked in nothing. `0005` starts it
from `hdmirx_audio_startup()` and from the plug-in/lock paths.

**`0005` may NOT wait on the audio work item — only on its completion.** This is
the one thing to get right if you ever touch that patch. `hdmi_codec_startup()`
calls `.audio_startup` (i.e. `hdmirx_audio_startup()`) with `hcp->lock` HELD, and
`hdmirx_delayed_work_audio()`'s success path calls `hdmirx_audio_handle_plugged_change()`
→ `plugged_cb()`, which takes `hcp->lock` **unconditionally**. Any
`flush_delayed_work()` / `flush_work()` / `cancel_delayed_work_sync()` on
`delayed_work_audio` from inside `hdmirx_audio_startup()` therefore deadlocks —
and deadlocks *only when audio is actually present*, because the no-audio path
never reaches `plugged_cb()`. The first version of `0005` did exactly this and
was corrected before any board test. The current version waits on
`hdmirx_dev->audio_ready`, which the work completes **before** that callback; do
not "simplify" that ordering, and do not reintroduce a flush. Teardown
(`hdmirx_plugout()`, `hdmirx_remove()`, the probe error path,
`hdmirx_runtime_suspend()`, `AUDIO_OFF`) goes through `hdmirx_audio_disarm_work()`,
which clears `audio_arm_allowed` under `audio_arm_lock` and only *then* calls
`cancel_delayed_work_sync()` — that order is what stops the startup retry loop
re-arming work behind a teardown. Lock order in this driver is
`work_lock → hcp->lock`; `hdmirx_audio_startup()` takes neither.

**`0005` is board-confirmed on one Radxa ROCK 5B+ test.** The standing gate is
now **PASSED**, not an open prerequisite: after a clean full `dd` reflash of
image `20260806T223730Z.raw`, CeraUI's live **Audio levels** meters showed real,
non-frozen fluctuating values across repeated samples (Channel 1 approximately
52–55/100; Channel 2 approximately 53–55/100). Kernel dmesg reported
`capture started: XFER=0x2 (cached; RXS=1)` with non-zero `RXFIFOLR=0xa`, and
there were zero `capture xfer failed` lines. ALSA ground truth from
`/proc/asound/card3/pcm0c/sub0/status` showed `hw_ptr` advancing
`15934388 → 16030718` over approximately `2.007s` (approximately 48000 Hz,
matching the driver's reported `restart audio fs(44100 -> 48000)` capture rate),
while `appl_ptr` tracked closely with bounded delay (`176 → 368`) and no
runaway drift. The capture owner was cerastream's own idle audio-meter sidecar
(pid 2907), proving the result through the production consumer rather than a
one-off manual `arecord`.

Keep these criteria as the permanent regression gate: a board must show
`hw_ptr` advancing, `RXS=1` with a non-zero `RXFIFOLR`, and no `capture xfer
failed` line.

**No MIT question arises here.** Both modified files carry plain
`SPDX-License-Identifier: GPL-2.0-only`, read from the tree at the pinned commit.
No new file, no SPDX change, no `MODULE_LICENSE` change, nothing under
`include/uapi/`. The sibling repo's long MIT caveat has no analogue on this path —
do not copy it over.

## PR TARGETING

This repository is **not a fork**; it was created directly under the CERALIVE
org, so `gh pr create` has no forked parent to mis-target. Be explicit anyway,
because the habit is what protects the repos that *are* forks:

```bash
gh pr create --repo CERALIVE/rk3588-vendor-kernel-patches --base main
gh pr view <n> --json url -q .url   # MUST be https://github.com/CERALIVE/...
```

Keep **only** `origin` (CERALIVE) attached at rest. Never add a remote named
`upstream`.

## CI

One workflow, `patch-apply.yml`, following the root CI/CD canon: `concurrency`
with `cancel-in-progress: true`; `push` constrained to `branches:` because a
`pull_request` trigger exists; top-level `permissions: contents: read`; actions
pinned to latest stable major; the BSP fetch cached. Jobs:

| Job | Asserts |
|-----|---------|
| `series-integrity` | `patches/` is generated from `upstream/`, payload-identical, and provenance matches `kernel-pin.env`; stdlib Python only |
| `preflight` | `kernel-pin.env` still matches `armbian/build`, the pinned commit is still on the branch, and PR #487 is still open — non-blocking on schedule, blocking on PR |
| `apply` | `scripts/apply.sh` — the real `git am` against the pinned commit |

`apply` is the gate. It runs the same script the README tells humans to run, so a
broken instruction is a red build.

There is **no build job**, deliberately. Adding one means a cross-compiler, a
defconfig, and a long job to prove something the image pipeline proves better.

## ANTI-PATTERNS

- Don't hand-edit `patches/` — regenerate from `upstream/`
- Don't add a conversion step to `build-series.py`; `upstream/` is already `git am`-able
- Don't add a `rebase/` engine unless a real conflict demands one
- Don't put first-party content in `upstream/`; first-party patches belong in `ceralive/`
- Don't pin `refs/pull/487/head`; pin the commit SHAs
- Don't claim PR #487 is merged — it is **open**
- Don't bump the pin when PR #487 merges — the patches become superseded; stop tracking new commits, but keep the repo and its content as useful historical reference
- Don't follow the branch tip downstream — pin `KERNEL_COMMIT`
- Don't confuse `rk-6.1-rkr5.1` with `rk-6.1-rkr6.1`
- Don't add this repo to `REPOS` or `versions.yaml` — it ships no artifact
- Don't copy the sibling repo's MIT caveat here; it does not apply
- Don't add this repo's content to `rk3588-kernel-patches`, or vice versa
- Don't add a `Co-authored-by:` or any AI/tool attribution to a commit
