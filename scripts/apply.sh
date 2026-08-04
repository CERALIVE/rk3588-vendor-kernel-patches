#!/usr/bin/env bash
#
# apply.sh — apply the series to the Armbian vendor BSP tree at the pinned commit.
#
# This is both the operator entry point and the CI gate, deliberately: a README
# instruction that CI does not execute is an instruction that rots. Everything the
# README tells a human to run, this script runs.
#
# Usage:
#   scripts/apply.sh                       # clone into ./.work/linux, then apply
#   scripts/apply.sh /path/to/linux        # apply to an existing tree
#   KEEP_TREE=1 scripts/apply.sh           # keep ./.work/linux for inspection
#
# It refuses to touch a tree with local modifications, and resets to the pinned
# commit before applying, so a rerun is always a clean run.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"

# shellcheck source=../kernel-pin.env
source "${ROOT}/kernel-pin.env"

WORKDIR="${ROOT}/.work"
TREE="${1:-${WORKDIR}/linux}"
CLONE_SOURCE="${KERNEL_CLONE_SOURCE:-${KERNEL_MIRROR}}"

log() { printf '\n== %s\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. Series integrity — patches/ must be exactly what build-series.py publishes
#    from upstream/, and it must not have changed what those commits do.
# ---------------------------------------------------------------------------
log "Verifying patches/ is generated, not hand-edited"
python3 "${HERE}/build-series.py" --check

log "Verifying the series changes nothing upstream/ did not already change"
python3 "${HERE}/verify-payload-parity.py"

# ---------------------------------------------------------------------------
# 2. Vendor BSP tree at the pinned COMMIT.
#
#    Not `clone --branch`: rk-6.1-rkr5.1 is a rolling branch with no tags, and
#    its tip has already moved past our pin. GitHub serves a shallow fetch of an
#    arbitrary reachable SHA, which gets the exact tree in ~1 min instead of a
#    multi-GB full clone.
# ---------------------------------------------------------------------------
if [[ ! -d "${TREE}/.git" ]]; then
	log "Fetching ${CLONE_SOURCE} at ${KERNEL_COMMIT} into ${TREE}"
	mkdir -p "${TREE}"
	git init --quiet "${TREE}"
	git -C "${TREE}" remote add origin "${CLONE_SOURCE}"
	git -C "${TREE}" fetch --depth 1 --quiet origin "${KERNEL_COMMIT}"
	git -C "${TREE}" checkout --quiet FETCH_HEAD
else
	log "Using existing kernel tree ${TREE}"
fi

cd "${TREE}"

if [[ -n "$(git status --porcelain)" ]]; then
	echo "error: ${TREE} has local changes; refusing to reset it." >&2
	echo "       Commit, stash, or point apply.sh at a scratch tree." >&2
	exit 1
fi

if ! git cat-file -e "${KERNEL_COMMIT}^{commit}" 2>/dev/null; then
	echo "error: ${TREE} does not contain ${KERNEL_COMMIT}." >&2
	echo "       That commit is the pinned base of the whole series." >&2
	echo "       Fetch it, or point apply.sh at a scratch tree." >&2
	exit 1
fi

# `git am` needs an identity even when nothing is committed by a human.
git config user.name  >/dev/null 2>&1 || git config user.name  "CeraLive Patch Gate"
git config user.email >/dev/null 2>&1 || git config user.email "noreply@ceralive.tv"

git am --abort >/dev/null 2>&1 || true
git checkout -f --quiet "${KERNEL_COMMIT}"
git clean -fdxq

log "Vendor BSP tree at ${KERNEL_BRANCH} @ ${KERNEL_COMMIT}"
git log --oneline -1 HEAD

# ---------------------------------------------------------------------------
# 3. Pre-conditions. Asserting the regression is actually PRESENT at the pin is
#    what stops this gate from going quietly green against a tree that never had
#    the bug — at which point `git am` succeeding would prove nothing at all.
# ---------------------------------------------------------------------------
log "Pre-apply checks (the regression must be present, or there is nothing to fix)"
prefail=0

if grep -q 'daidrv\[i\]\.capture\.channels_min = 0;' sound/soc/codecs/hdmi-codec.c; then
	echo "  ok      ${REGRESSION_COMMIT:0:12}'s unconditional capture zeroing is present"
else
	echo "  MISSING the unconditional capture zeroing this series exists to remove." >&2
	echo "          Either the pin moved, or PR #${UPSTREAM_PATCHES_PR} (or an" >&2
	echo "          equivalent) already landed. Re-pin deliberately." >&2
	prefail=1
fi

if grep -q 'no_i2s_capture' include/sound/hdmi-codec.h; then
	echo "  UNEXPECTED no_i2s_capture already exists in include/sound/hdmi-codec.h" >&2
	echo "             The fix is already in this tree; the series will not apply." >&2
	prefail=1
else
	echo "  ok      the per-instance no_i2s_* flags are absent, as expected"
fi

(( prefail == 0 )) || exit 1

# ---------------------------------------------------------------------------
# 4. Apply. Order is patches/series.
# ---------------------------------------------------------------------------
mapfile -t SERIES < <(grep -v '^\s*#' "${ROOT}/patches/series" | grep -v '^\s*$')
log "Applying ${#SERIES[@]} patches with git am"

declare -a ABS=()
for name in "${SERIES[@]}"; do
	ABS+=("${ROOT}/patches/${name}")
done

if ! git am --keep-non-patch "${ABS[@]}"; then
	echo >&2
	echo "error: the series does not apply to ${KERNEL_COMMIT}." >&2
	echo "       Failing patch: $(git am --show-current-patch=raw 2>/dev/null |
		sed -n 's/^Subject: //p' | head -1)" >&2
	echo "       Inspect with: git -C ${TREE} am --show-current-patch=diff" >&2
	echo "       Do NOT invent a resolution and do NOT hand-edit patches/." >&2
	echo "       Re-export from armbian/linux-rockchip at the pinned SHAs, or" >&2
	echo "       re-pin KERNEL_COMMIT deliberately and re-run this gate." >&2
	git am --abort >/dev/null 2>&1 || true
	exit 1
fi

log "Applied cleanly"
git log --oneline "${KERNEL_COMMIT}..HEAD"
echo
git diff --stat "${KERNEL_COMMIT}..HEAD"

# ---------------------------------------------------------------------------
# 5. Post-conditions. The failure mode this series fixes is SILENT — the codec
#    binds, nothing errors, and /proc/asound/pcm simply shows a line ending in a
#    bare colon with no substreams. So assert the actual mechanism, not just that
#    `git am` returned 0.
# ---------------------------------------------------------------------------
log "Post-apply checks"
fail=0

check_absent() {
	local pattern="$1" file="$2" label="$3"
	if grep -q "${pattern}" "${file}"; then
		echo "  STILL PRESENT ${label} in ${file}" >&2
		fail=1
	else
		echo "  ok      ${label} is gone from ${file}"
	fi
}

check_present() {
	local pattern="$1" file="$2" label="$3"
	if grep -q "${pattern}" "${file}"; then
		echo "  ok      ${label}"
	else
		echo "  MISSING ${label} in ${file}" >&2
		fail=1
	fi
}

# 5a. The regression itself: the unconditional zeroing must be gone, for BOTH the
#     i2s and the spdif DAI, along with the comment that justified it.
check_absent 'daidrv\[i\]\.capture\.channels_min = 0;' \
	sound/soc/codecs/hdmi-codec.c "unconditional capture.channels_min zeroing"
check_absent 'daidrv\[i\]\.capture\.channels_max = 0;' \
	sound/soc/codecs/hdmi-codec.c "unconditional capture.channels_max zeroing"
check_absent 'Disable capture for HDMI-TX' \
	sound/soc/codecs/hdmi-codec.c "the HDMI-TX-only justification comment"

# 5b. The replacement: per-instance opt-out flags, declared and honoured.
for flag in no_i2s_playback no_i2s_capture no_spdif_playback no_spdif_capture; do
	check_present "uint ${flag}:1;" include/sound/hdmi-codec.h \
		"hdmi_codec_pdata declares ${flag}"
	check_present "hcd->${flag}" sound/soc/codecs/hdmi-codec.c \
		"hdmi_codec_probe honours ${flag}"
done

# 5c. Patch 2: startup/shutdown no-op on an unsupported direction.
check_present 'bool has_capture = !hcp->hcd.no_i2s_capture;' \
	sound/soc/codecs/hdmi-codec.c "startup/shutdown compute has_capture"
if [[ "$(grep -c '(has_playback && tx) || (has_capture && !tx)' \
	sound/soc/codecs/hdmi-codec.c)" == "2" ]]; then
	echo "  ok      both hdmi_codec_startup and hdmi_codec_shutdown are guarded"
else
	echo "  MISSING the direction guard in BOTH startup and shutdown" >&2
	fail=1
fi

# 5d. The whole point: rk_hdmirx must still register the codec, and must NOT opt
#     out of capture. If a future BSP revision sets no_i2s_capture there, this
#     series applies cleanly and HDMI-RX audio stays broken anyway.
RK_HDMIRX="drivers/media/platform/rockchip/hdmirx/rk_hdmirx.c"
check_present 'HDMI_CODEC_DRV_NAME' "${RK_HDMIRX}" \
	"rk_hdmirx registers an hdmi-audio-codec device"

if awk '/struct hdmi_codec_pdata codec_data = \{/,/\};/' "${RK_HDMIRX}" |
	grep -qE 'no_i2s_capture|no_i2s_playback|no_spdif_capture|no_spdif_playback'; then
	echo "  BAD     rk_hdmirx now sets a no_* flag; HDMI-RX capture would stay dead" >&2
	fail=1
else
	echo "  ok      rk_hdmirx sets no no_* flag, so its capture PCM survives"
fi

if awk '/struct hdmi_codec_pdata codec_data = \{/,/\};/' "${RK_HDMIRX}" |
	grep -q '\.i2s = 1,'; then
	echo "  ok      rk_hdmirx still requests the i2s DAI"
else
	echo "  MISSING .i2s = 1 in rk_hdmirx's hdmi_codec_pdata" >&2
	fail=1
fi

# 5e. The partial-backport interlock. Upstream f77a066f ALSO added a null-guard
#     loop around snd_soc_dapm_add_routes(), because memset-ing a direction to
#     zero leaves route[].source/sink NULL. PR #487 did not carry that hunk, so
#     this tree still calls add_routes(dapm, route, 2) unconditionally. That is
#     harmless while nothing sets a no_* flag — and nothing does — but the flags
#     exist precisely so a driver CAN opt in. Fail loudly if one ever does
#     without the guard, instead of shipping a NULL deref. See docs/PROVENANCE.md §5.
if grep -q 'snd_soc_dapm_add_routes(dapm, &route\[i\], 1)' \
	sound/soc/codecs/hdmi-codec.c; then
	echo "  ok      the upstream null-route guard is present; no_* opt-in is safe"
elif grep -rqE '\.no_(i2s|spdif)_(playback|capture)[[:space:]]*=' \
	--include='*.c' drivers/ sound/; then
	echo "  BAD     a driver opts in to a no_* flag, but hdmi_codec_dai_probe()" >&2
	echo "          still registers both DAPM routes unconditionally. Upstream's" >&2
	echo "          null-guard hunk from f77a066f was not backported by PR #487." >&2
	fail=1
else
	echo "  ok      no driver opts in to a no_* flag, so the omitted null-route"
	echo "          guard from f77a066f is not reachable in this tree"
fi

(( fail == 0 )) || exit 1

if [[ -z "${KEEP_TREE:-}" && "${TREE}" == "${WORKDIR}/linux" ]]; then
	log "Removing ${WORKDIR} (set KEEP_TREE=1 to keep it)"
	cd "${ROOT}"
	rm -rf "${WORKDIR}"
fi

log "OK — series applies to ${KERNEL_BRANCH} @ ${KERNEL_COMMIT}"
