# Provenance and licence audit

**Audited:** 2026-08-04
**Subject:** the three-patch series: two backport commits carried in `upstream/`,
taken from `armbian/linux-rockchip` pull request
[#487](https://github.com/armbian/linux-rockchip/pull/487) — **OPEN, not merged** —
and one first-party patch in `ceralive/`.

This is a **factual ledger**, not legal advice and not a clearance. It records
what was examined, what was found, and which questions remain open. No lawyer has
reviewed it and no legal sign-off is claimed or implied. Where something is
uncertain it is written down as uncertain.

Every fact below was read out of the actual files at the actual pinned commits,
in a real clone. Nothing is paraphrased from a summary.

---

## 1. What this repository redistributes

| Kind | Where | What it is |
|------|-------|-----------|
| Git mailbox patches, verbatim | `upstream/*.patch` | `git format-patch` output for two real commits in `armbian/linux-rockchip`, byte-for-byte |
| Git mailbox patches, published | `patches/*.patch` | **Byte-identical copies** of `upstream/` and `ceralive/`, plus a generated `series` file |
| CeraLive-authored | `ceralive/`, `scripts/`, `docs/`, `kernel-pin.env`, `.github/` | CeraLive patch, packaging, tooling, and documentation |

No compiled kernel, `.deb`, or binary blob is redistributed. This repository
produces patch text only.

`patches/` being a byte-identical copy is not laziness — it is what the source
being real git commits actually buys us. See [`README.md`](../README.md) →
"Differences from the mainline sibling repo".

---

## 2. The two commits, in full

### 2.1 `0001` — restore the per-instance direction flags

| | |
|---|---|
| Armbian commit | `e61f83c2a1d6e549be8a37ccc4ee3bd7d5957303` |
| Subject | `ASoC: hdmi-codec: Allow playback and capture to be disabled` |
| Author (git) | **Mark Brown** `<broonie@kernel.org>`, 2022-11-30 |
| Committer (git) | Stepan Mazurov |
| Declares | `commit f77a066f4ed307db93aafee621e2683c3bda98ce upstream.` |
| Upstream trailers | `Reviewed-by: Russell King (Oracle) <rmk+kernel@armlinux.org.uk>`, `Link: https://lore.kernel.org/r/20221130184644.464820-2-broonie@kernel.org`, `Signed-off-by: Mark Brown <broonie@kernel.org>` |
| Backport trailers | `[smazurov@gmail.com: …]` annotation, `Tested-by: Stepan Mazurov <smazurov@gmail.com>`, `Signed-off-by: Stepan Mazurov <smazurov@gmail.com>` |

`f77a066f4ed307db93aafee621e2683c3bda98ce` was confirmed to exist in
`torvalds/linux` with the same author, date and subject.

### 2.2 `0002` — no-op on an unsupported direction

| | |
|---|---|
| Armbian commit | `2f2652ff988b84db627909eac1e6a4ef644144a2` |
| Subject | `ASoC: hdmi-codec: only startup/shutdown on supported streams` |
| Author (git) | **Emil Abildgaard Svendsen** `<EMAS@bang-olufsen.dk>`, 2023-03-09 |
| Committer (git) | Stepan Mazurov |
| Declares | `commit e041a2a550582106cba6a7c862c90dfc2ad14492 upstream.` |
| Upstream trailers | `Signed-off-by: Emil Svendsen <emas@bang-olufsen.dk>`, `Link: https://lore.kernel.org/r/20230309065432.4150700-2-emas@bang-olufsen.dk`, `Signed-off-by: Mark Brown <broonie@kernel.org>` |
| Backport trailers | `[smazurov@gmail.com: …]` annotation, `Tested-by: Stepan Mazurov <smazurov@gmail.com>`, `Signed-off-by: Stepan Mazurov <smazurov@gmail.com>` |

`e041a2a550582106cba6a7c862c90dfc2ad14492` was confirmed to exist in
`torvalds/linux` with the same author and subject.

Mark Brown is the ASoC subsystem maintainer; he is the **author** of `0001` and
the applying maintainer who signed off `0002`. That is the ordinary shape of a
real upstream ASoC commit, and it is the strongest single provenance signal here:
these are not community patches of unknown origin, they are mainline Linux.

### 2.3 `0003` — first-party DMA-budget fix

| | |
|---|---|
| Source lane | `ceralive/` |
| Author (git) | **CeraLive kernel patches** `<ceralive-patches@ceralive.tv>` |
| Origin | Armbian `linux-rockchip` issue [#367](https://github.com/armbian/linux-rockchip/issues/367), reported by **YumingChang02** on 2025-06-06 |
| Change | Raises `MCODE_BUFF_PER_REQ` in `drivers/dma/pl330.c` from 256 to 512 and `MAXBURST_PER_FIFO` in `sound/soc/rockchip/rockchip_i2s_tdm.c` from 8 to 16 |
| Upstream status | No mergeable or citable source commit; the origin is the issue comment and proposed diff, not a commit |

`0003` is deliberately not placed in `upstream/`: that lane is reserved for
verbatim mailboxes whose provenance is a real Armbian commit. The sibling
mainline repository uses the same `ceralive/` lane for first-party patches with
no upstream counterpart. This patch was generated from an actual local kernel
commit after applying `0001` and `0002`, not hand-written.

The board evidence proves the PL330 descriptor rejection is gone: the failing
ffmpeg request went from 8/8 `mcbufsz (440/256)` / `Bad Desc` failures to 0/1,
and six capture runs produced no `mcbufsz`, `Bad Desc`, or `FIFO Overrun` lines.
The `MAXBURST_PER_FIFO` half remains as harmless prior art and was not proven in
isolation. The evidence file is
`vendor-kernel-hdmi-audio-bench-boot-proof-2.md`; it also records that the test
source reported no embedded audio, so this is not an end-to-end audio claim.

### 2.4 Attribution summary

| Person / body | Role |
|---|---|
| **Mark Brown** `<broonie@kernel.org>` | Author of `0001`; upstream ASoC maintainer who applied and signed off `0002` |
| **Emil Abildgaard Svendsen** `<emas@bang-olufsen.dk>` (Bang & Olufsen) | Author of `0002` |
| **Russell King (Oracle)** `<rmk+kernel@armlinux.org.uk>` | Reviewer of `0001` upstream |
| **Stepan Mazurov** (`smazurov`) `<smazurov@gmail.com>` | Backported both commits onto `rk-6.1-rkr5.1`; author of PR #487; the `Tested-by` on both |
| **The Armbian project** | Owns `armbian/linux-rockchip`, the fork these commits live in |
| **Texas Instruments / Jyri Sarha** | Original copyright holder of the two files being modified |
| CeraLive | First-party author of `0003`; packaging, pinning, auditing, and CI. |

---

## 3. The central risk: this tracks an UNMERGED pull request

**PR #487 is OPEN.** It has not been merged into `rk-6.1-rkr5.1`, and nothing
here should be read as claiming otherwise. Its base branch is `rk-6.1-rkr5.1`,
its head repository is `smazurov/linux-rockchip`, and it carries exactly two
commits — the two in `upstream/`.

The obvious hazard with tracking a live PR is that a PR is a *moving reference*.
`refs/pull/487/head` points at whatever the contributor last pushed; a rebase or
a force-push silently changes what that ref resolves to, and anything pinned to
it would follow along without a diff to review.

**That risk is contained here, by construction, because this repository pins
COMMIT SHAs and never the PR ref.** `kernel-pin.env` records
`PATCH_COMMIT_1` / `PATCH_COMMIT_2` as full 40-character SHAs. A git commit SHA is
a hash of its own content and history — it cannot be made to name different
content. So:

- if smazurov force-pushes PR #487 tomorrow, this repository keeps applying the
  exact two commits audited above, unchanged;
- `scripts/verify-payload-parity.py` independently re-asserts that every patch
  file's mbox delimiter is one of those two pinned SHAs, so a swapped file fails
  the gate rather than passing review;
- `git format-patch` output was taken from a real clone, so the mailbox contents
  are reproducible by anyone: fetch the SHA, run the same command, byte-compare.

What the pin does **not** protect against is the PR's *fate*, and that genuinely
matters in both directions:

| If PR #487 … | Consequence |
|---|---|
| **merges** into `rk-6.1-rkr5.1` | Good news. Any pin taken after the merge already carries the fix, and applying this series on top would fail. Re-pin `KERNEL_COMMIT` past the merge and retire this repository rather than double-applying. |
| **closes unmerged** | The fix is unmaintained upstream. This repository is then the only carrier, which is fine mechanically but should be a conscious decision, not a drift. |
| **is rewritten** | Irrelevant to what we apply, but the rewrite may be a better fix. Worth reading before the next pin bump. |

`scripts/preflight.sh` re-reads the PR's state on every run and fails on a change
away from `UPSTREAM_PATCHES_PR_STATE="open"`, precisely so none of the three
outcomes above can happen silently. CI runs it weekly.

---

## 4. Licence facts

### 4.1 Collection-level licence: present, unlike the sibling repo

Both source repositories are Linux kernel trees and ship the kernel's own
`COPYING`, read at the pinned commit:

```
The Linux Kernel is provided under:

	SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note
```

This is a materially better position than the sibling
`CERALIVE/rk3588-kernel-patches`, whose upstream is a bare patch repository with
**no `LICENSE` file at all**, forcing that audit to rely entirely on per-file
SPDX headers. Here there is a collection-level grant *and* per-file headers, and
they agree.

### 4.2 Per-file licence markers

The series modifies exactly two files. Both already exist in mainline Linux and
both keep their existing licence — read directly from the tree at
`95e85f6cb496c75807c5b16f158853578e7e7d1b`:

| File | SPDX (verbatim) | Copyright | Author |
|------|-----------------|-----------|--------|
| `sound/soc/codecs/hdmi-codec.c` | `// SPDX-License-Identifier: GPL-2.0-only` | Copyright (C) 2015 Texas Instruments Incorporated - https://www.ti.com/ | Jyri Sarha `<jsarha@ti.com>` |
| `include/sound/hdmi-codec.h` | `/* SPDX-License-Identifier: GPL-2.0-only */` | Copyright (C) 2014 Texas Instruments Incorporated - https://www.ti.com | Jyri Sarha `<jsarha@ti.com>` |

**`GPL-2.0-only`, not `GPL-2.0+`, and not a dual grant.** That was read off the
actual first line of each file at the pinned commit, not assumed from the
kernel's general licence policy.

### 4.3 What the series does NOT do

- adds **no** new source file;
- alters **no** SPDX line;
- touches **no** `MODULE_LICENSE` value;
- touches **nothing** under `include/uapi/`, so the `Linux-syscall-note`
  exception never comes into play.

### 4.4 Redistribution basis

Straightforward, and much simpler than the sibling repository's case:

- both modified files are `GPL-2.0-only`;
- the Linux kernel as a whole is `GPL-2.0 WITH Linux-syscall-note`;
- a patch against those files is a derivative of them, so distributing it under
  GPL-2.0 terms is exactly what the licence contemplates.

There is **no MIT branch to elect** and therefore **no MIT caveat** — the
`(GPL-2.0+ OR MIT)` disjunction that dominates the sibling repository's
`PROVENANCE.md` §5.1 simply does not arise on this code path. This repository is
distributed as GPL-2.0-only kernel patches.

---

## 5. Finding: `0001` is a PARTIAL backport of `f77a066f`

This was found by diffing the backport's payload against the real upstream commit
fetched from `torvalds/linux`, not by reading either commit message.

Upstream `f77a066f4ed307db93aafee621e2683c3bda98ce` changes **two** things:

1. it adds the four `no_i2s_playback` / `no_i2s_capture` / `no_spdif_playback` /
   `no_spdif_capture` flags and honours them in `hdmi_codec_probe()`; **and**
2. it rewrites `hdmi_codec_dai_probe()`'s DAPM route registration to skip routes
   whose `source` or `sink` is NULL:

   ```c
   /* One of the directions might be omitted for unidirectional DAIs */
   for (i = 0; i < ARRAY_SIZE(route); i++) {
           if (!route[i].source || !route[i].sink)
                   continue;
           ret = snd_soc_dapm_add_routes(dapm, &route[i], 1);
           ...
   ```

   That second hunk is not decoration. The route array is built from
   `dai->driver->playback.stream_name` and `dai->driver->capture.stream_name`, and
   the first hunk `memset`s a whole direction to zero when its flag is set — which
   makes the corresponding `stream_name` NULL.

**PR #487 carries hunk 1 and not hunk 2.** Verified post-apply: the tree still
calls `snd_soc_dapm_add_routes(dapm, route, 2)` unconditionally.

**Is that a live bug on the CeraLive path? No — verified, not assumed.**

- `rk_hdmirx` (`drivers/media/platform/rockchip/hdmirx/rk_hdmirx.c`) registers its
  codec with `.ops`, `.spdif = 1`, `.i2s = 1`, `.max_i2s_channels = 8`, `.data` —
  and **no** `no_*` flag. So neither direction is zeroed and neither
  `stream_name` goes NULL.
- A tree-wide grep after applying the series finds **no driver anywhere** setting
  any of the four flags. Before the series they did not exist; after it, nothing
  opts in yet.

So the omitted hunk is currently unreachable. It becomes reachable the moment
someone takes `0001`'s own commit message up on its offer — *"Drivers that need
the original PulseAudio workaround (the RK3576 HDMI-TX case) can opt back in by
setting `hdmi_codec_pdata.no_i2s_capture = 1` explicitly"* — because that is
exactly the case the null-guard exists for.

`scripts/apply.sh` therefore asserts the pair: if the null-guard is absent **and**
any driver sets a `no_*` flag, the gate fails. That is a real interlock derived
from a real finding, not a hypothetical.

**This is reported here rather than fixed.** Fixing it would mean editing patch
content, which this repository does not do (§6). If it ever needs fixing, the
right move is to backport the missing hunk as a *third* patch with its own
provenance, or to ask PR #487 to carry it.

`0002` was checked the same way and is a **complete** payload match with upstream
`e041a2a550582106cba6a7c862c90dfc2ad14492`; the only difference is where a blank
line falls, because the Armbian tree carries an extra `tx_dlp` early-return that
mainline does not.

---

## 6. What this repository does and does not change

- Patch behaviour is **not** modified. `patches/` is a byte-identical copy of
  the matching `upstream/` or `ceralive/` source lane, and
  `scripts/verify-payload-parity.py` proves the added/removed line sets match,
  independently of the script that produced them.
- No SPDX identifier, copyright line, or existing kernel trailer is added,
  removed, or altered. `0003` has no invented `Signed-off-by` trailer: it is a
  first-party packaging patch, not a claim that CeraLive submitted an upstream
  kernel change.
- Nothing is relicensed. `LICENSE` describes terms the imported material already
  carries; it grants nothing new.
- The series is **not** claimed to be upstream-mergeable or upstream-bound. The
  first two patches are in front of Armbian as PR #487; `0003` originates in an
  issue comment and has no upstream commit counterpart.
- No `Co-authored-by:` or AI/tool attribution appears in any commit here, per the
  workspace-wide rule in the root `AGENTS.md`.

---

## 7. Open questions (not closed by this audit)

1. **PR #487's fate.** Open at audit time. Watched by `scripts/preflight.sh`, but
   whether Armbian merges it is not ours to decide.
2. **Whether the missing null-guard hunk (§5) should be carried here.** Deferred
   deliberately; the interlock in `apply.sh` makes the omission loud rather than
   silent, which is the honest interim position.
3. **The backport annotations were not independently reproduced.** smazurov's
   bracketed notes describe a bisect on an Orange Pi 5 Ultra
   (`linux-image-vendor-rk35xx` 25.8.2 good, 26.2.1 broken) and a forum report.
   The *symptom* was independently confirmed on CeraLive's own Rock 5B+ running
   `6.1.115-vendor-rk35xx` — `/proc/asound/pcm` shows `03-00: rockchip,hdmiin
   i2s-hifi-0 :` with zero substreams under a locked 1920x1080p59.94 input — and
   the regression commit `78c67d98f221895336d41d8799b38eff6b6b7b4e` (PR #430,
   merged 2025-11-20) was read directly. The *bisect itself* was not re-run.
4. **End-to-end HDMI audio remains open.** The board evidence for `0003` proves
   the PL330 descriptor rejection is gone, but the tested HDMI source reported
   no embedded audio. The MAXBURST half was not proven in isolation; see
   [`README.md`](../README.md) → "Scope".
5. **No legal review.** None requested, none obtained, none implied.
