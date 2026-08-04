# Preflight — how the Armbian rk3588 `vendor` kernel was resolved

Everything in [`kernel-pin.env`](../kernel-pin.env) was **read out of Armbian's
own configuration at a recorded revision**, not copied from a wiki or from a
previous investigation. This page shows the derivation so it can be re-checked.

Re-run it yourself at any time:

```bash
scripts/preflight.sh          # against the pinned ARMBIAN_BUILD_REV
scripts/preflight.sh --head   # against armbian/build's current main
```

The `--head` form is the one that answers *"has Armbian moved the rk3588 vendor
branch since this was pinned?"*, and it is what CI runs on a schedule.

---

## Resolved on 2026-08-04

**Framework revision:** `armbian/build` `main` @ `5e2fa21ab509e9cf6afb05f3df46c9bd2b0cfa39`
(committed 2026-08-04, and the tip of `main` at the time of this audit).

### Boards

Both CeraLive RK3588 targets resolve to the same Armbian family **and to the same
vendor kernel package**, so one mapping covers both.

| Armbian board config | `BOARDFAMILY` | `KERNEL_TARGET` |
|---|---|---|
| `config/boards/rock-5b-plus.conf` | `rockchip-rk3588` | `vendor,current,edge` |
| `config/boards/orangepi5-plus.conf` | `rockchip-rk3588` | `current,edge,vendor` |

`vendor` is a supported target on both, and is what the shipped CeraLive image
uses.

### The derivation chain

**1. `config/sources/families/rockchip-rk3588.conf`** — lines 32-42

Unlike `edge` (see the sibling repo's own `docs/PREFLIGHT.md`, where the family
config has no `edge)` arm at all and the mapping is decided by a common include),
`vendor` **is** handled by the rk3588 family config directly, and it sets every
value explicitly:

```bash
	vendor)
		BOOTSCRIPT='boot-rk35xx.cmd:boot.cmd'
		BOOTDIR='u-boot-rockchip64'
		declare -g KERNEL_MAJOR_MINOR="6.1"    # Major and minor versions of this kernel.
		declare -g -i KERNEL_GIT_CACHE_TTL=120 # 2 minutes; this is a high-traffic repo
		KERNELSOURCE='https://github.com/armbian/linux-rockchip.git'
		KERNELBRANCH='branch:rk-6.1-rkr5.1'
		KERNELPATCHDIR='rk35xx-vendor-6.1'
		LINUXFAMILY=rk35xx
		;;
```

Line 10 of the same file sources `include/rockchip64_common.inc` *before* this
`case`, but the include's own arms only cover `current`, `edge` and
`bleedingedge`. Its line 24 says so explicitly:

> `# Important, we don't set LINUXFAMILY and LINUXCONFIG -- unless it is current or edge.`

So for `vendor` the include contributes nothing to the mapping.

**2. `config/sources/common.conf`** — line 134

`LINUXCONFIG` is the one value the `vendor)` arm does *not* set, so it falls
through to the framework default:

```bash
	LINUXCONFIG="linux-${LINUXFAMILY}-${BRANCH}"
```

→ `linux-rk35xx-vendor`, and `config/kernel/linux-rk35xx-vendor.config` exists in
the tree, which confirms the derivation rather than merely permitting it.

**3. `lib/functions/compilation/kernel-debs.sh`** — line 72

The Debian package name:

```bash
	create_kernel_deb "linux-image-${BRANCH}-${LINUXFAMILY}" ...
```

→ **`linux-image-vendor-rk35xx`**, which is exactly the package the shipped
CeraLive image installs.

**4. `lib/functions/artifacts/artifact-kernel.sh`** — line 95

Where user patches are read from:

```bash
	display_alert "User patches directory for kernel" "${USERPATCHES_PATH}/kernel/${KERNELPATCHDIR}" "info"
```

→ `userpatches/kernel/rk35xx-vendor-6.1/`. Note this is a **top-level**
`patch/kernel/` family directory, *not* one under `patch/kernel/archive/` the way
the mainline `rockchip64-*` families are. Both forms exist in the tree
simultaneously; using the wrong one means the patches are silently not applied.

---

## Resolved values

| What | Value |
|---|---|
| Armbian branch | `vendor` |
| `KERNEL_MAJOR_MINOR` | `6.1` |
| `LINUXFAMILY` | `rk35xx` |
| `LINUXCONFIG` | `linux-rk35xx-vendor` (framework default; not set by the family) |
| Kernel config source | `config/kernel/linux-rk35xx-vendor.config` |
| `KERNELPATCHDIR` | `rk35xx-vendor-6.1` |
| Armbian patch dir | `patch/kernel/rk35xx-vendor-6.1/` |
| User patch dir | `userpatches/kernel/rk35xx-vendor-6.1/` |
| Debian package | `linux-image-vendor-rk35xx` |
| `KERNELSOURCE` | `https://github.com/armbian/linux-rockchip.git` |
| `KERNELBRANCH` (Armbian's) | `branch:rk-6.1-rkr5.1` — a **rolling branch** |
| **This repository's pin** | **`95e85f6cb496c75807c5b16f158853578e7e7d1b`** |

---

## `rk-6.1-rkr5.1` vs `rk-6.1-rkr6.1` — different branches, not aliases

This is the single easiest thing to get wrong about the vendor track, so it is
pinned down here rather than left to inference.

- `rk-6.1-rkr5.1` is what `armbian/build` resolves `BRANCH=vendor` to on
  `rockchip-rk3588` at the revision above. It produces **6.1.115**.
- `rk-6.1-rkr6.1` is a **separate, diverged branch**, introduced later
  (`armbian/build` PR #8719, merged 2025-10-05). It produces **6.1.118**.

They are not two names for one branch, and a commit on one is not necessarily on
the other. Every coordinate in this repository is `rkr5.1`; `scripts/preflight.sh`
asserts the resolved `KERNELBRANCH` does not contain `rk-6.1-rkr6.1`
(`KERNELBRANCH_NOT` in `kernel-pin.env`) so a switch cannot pass quietly.

> Note that the sibling repo `CERALIVE/rk3588-kernel-patches` states in its
> `AGENTS.md` that the `78c67d98f221` regression "breaks HDMI-RX capture on the
> **vendor** BSP (`rk-6.1-rkr6.1`)". The regression is real on both branches —
> `78c67d98` was merged to `rk-6.1-rkr5.1` via PR #430 — but the branch this
> project actually ships is `rkr5.1`, and that is what this repository targets.

---

## Why a COMMIT is pinned when Armbian uses a branch

Armbian tracks `rk-6.1-rkr5.1`, which moves with every BSP push, and the branch
carries **no tags at all** — so unlike the mainline sibling repo, there is no
`v7.1.5`-shaped thing to pin. A series verified against "whatever `rk-6.1-rkr5.1`
was that morning" is not verified against anything reproducible.

So this repository pins one immutable commit:

```
95e85f6cb496c75807c5b16f158853578e7e7d1b
"ata: ahci: force 32-bit DMA for JMicron JMB582/JMB585 (#504)"
committed 2026-06-14T17:47:08Z
```

**Why that commit specifically.** The production CeraLive Rock 5B+ runs
`6.1.115-vendor-rk35xx`, and its kernel reports a build timestamp of
`Sun Jun 14 17:47:08 UTC 2026`. That commit's timestamp is
`2026-06-14T17:47:08Z` — the same second. It is the commit
`linux-image-vendor-rk35xx` 6.1.115 was built from, and the `Makefile` at that
commit reads `VERSION = 6 / PATCHLEVEL = 1 / SUBLEVEL = 115`, which confirms it
independently.

At audit time the branch tip had already moved on to
`5280f9b4336199c4025c8eed894d2b4e2268dcc6` (2026-07-15). `preflight.sh` checks
that the pinned commit is still an ancestor of the branch — `behind` or
`identical` is fine, anything else means a force-push or a rename and is a hard
failure.

---

## The patch source forked 17 commits earlier — and that is fine

PR #487's branch forked from `9bd271d7fa4aab0cffd2ac6f1fd8e26c857c46c2`, which
GitHub's compare API reports as **17 commits behind** our pinned base. So the two
patches were authored against a slightly older tree than the one we apply them
to.

That is a fact worth knowing, not a problem to route around: `scripts/apply.sh`
runs the real `git am` against the real pinned tree and it applies cleanly, with
no re-anchoring and no rebase rules. **The gate proves it; nothing here assumes
it.** If a future pin bump ever does drift, the gate goes red and the drift gets
handled deliberately.

---

## Relationship to the shipped image

Unlike the mainline sibling repo, this one targets **exactly the kernel the
shipped CeraLive image runs today**: the Armbian vendor BSP,
`linux-image-vendor-rk35xx` 6.1.115, per image-pipeline Decision D3.

That makes it the higher-stakes of the two patch packages and also the more
directly useful one — the regression it fixes is not theoretical, it is on the
board right now.

It does **not**, however, change the shipped image on its own. Nothing here
builds a kernel or produces a `.deb`. Wiring this series into
`image-building-pipeline`'s vendor-kernel build is separate, unfinished work.
