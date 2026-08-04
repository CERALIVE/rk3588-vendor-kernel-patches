#!/usr/bin/env bash
#
# preflight.sh — re-resolve the Armbian rk3588 `vendor` kernel mapping from source
# and report drift against kernel-pin.env.
#
# The vendor mapping is easier to read than the `edge` one its sibling repo
# resolves — rockchip-rk3588.conf handles `vendor` in its OWN `case $BRANCH`, so
# every value is right there — but two things still move and both matter:
#
#   * KERNELBRANCH. `rk-6.1-rkr5.1` and `rk-6.1-rkr6.1` are DIFFERENT, diverged
#     BSP branches, not aliases. rkr6.1 produces 6.1.118; our board runs 6.1.115
#     off rkr5.1. If the family config ever switches, this repo's pinned base
#     commit stops being on the branch Armbian builds and the whole package is
#     aimed at a kernel nobody ships.
#   * The patch source is an OPEN pull request. If armbian/linux-rockchip merges
#     PR #487, the fix lands in the branch itself and this repo becomes redundant
#     for any pin taken after the merge — which is good news, but it is news, and
#     nobody would notice without a watcher.
#
# Read-only. Never edits kernel-pin.env; it prints what it found and exits
# non-zero on a mismatch so CI can fail on it.
#
# Usage:
#   scripts/preflight.sh              # check against the pinned ARMBIAN_BUILD_REV
#   scripts/preflight.sh --head       # check against armbian/build's CURRENT main
#
# `--head` is the one that matters when deciding to bump: it answers "has Armbian
# moved the rk3588 vendor branch since we pinned?".

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"

# shellcheck source=../kernel-pin.env
source "${ROOT}/kernel-pin.env"

RAW="https://raw.githubusercontent.com/armbian/build"
API="https://api.github.com/repos/armbian/build"
KERNEL_API="https://api.github.com/repos/armbian/linux-rockchip"

# Unauthenticated api.github.com is 60 req/h per IP, which shared CI runners do
# exhaust. Use the workflow token when there is one so this cannot flake.
declare -a AUTH=()
[[ -n "${GITHUB_TOKEN:-}" ]] && AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN}")

rev="${ARMBIAN_BUILD_REV}"
mode="pinned"
if [[ "${1:-}" == "--head" ]]; then
	mode="current HEAD"
	rev="$(curl -fsSL "${AUTH[@]}" "${API}/commits/main" |
		sed -n 's/.*"sha": *"\([0-9a-f]\{40\}\)".*/\1/p' | head -1)"
	[[ -n "${rev}" ]] || { echo "error: could not resolve armbian/build main" >&2; exit 2; }
fi

echo "armbian/build @ ${rev} (${mode})"
echo

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

fetch() {
	curl -fsSL "${RAW}/${rev}/$1" -o "${tmp}/$(basename "$1")" ||
		{ echo "error: cannot fetch $1 at ${rev}" >&2; exit 2; }
}

fetch config/sources/families/rockchip-rk3588.conf
fetch config/sources/common.conf
for board in ${ARMBIAN_BOARDS}; do fetch "config/boards/${board}.conf"; done

status=0
check() {
	local label="$1" want="$2" got="$3"
	if [[ "${want}" == "${got}" ]]; then
		printf '  ok    %-26s %s\n' "${label}" "${got}"
	else
		printf '  DRIFT %-26s pinned=%s  actual=%s\n' "${label}" "${want}" "${got}" >&2
		status=1
	fi
}

# --- boards -----------------------------------------------------------------
echo "Board -> family"
for board in ${ARMBIAN_BOARDS}; do
	family="$(sed -n 's/^BOARDFAMILY="\(.*\)"$/\1/p' "${tmp}/${board}.conf" | head -1)"
	targets="$(sed -n 's/^KERNEL_TARGET="\(.*\)"$/\1/p' "${tmp}/${board}.conf" | head -1)"
	check "${board} family" "${ARMBIAN_BOARDFAMILY}" "${family}"
	if [[ ",${targets}," == *",${ARMBIAN_BRANCH},"* ]]; then
		printf '  ok    %-26s KERNEL_TARGET=%s\n' "${board} supports vendor" "${targets}"
	else
		printf '  DRIFT %-26s KERNEL_TARGET=%s lacks %s\n' \
			"${board}" "${targets}" "${ARMBIAN_BRANCH}" >&2
		status=1
	fi
done

# --- the family config's own vendor) arm -------------------------------------
# Unlike `edge`, `vendor` IS handled by the rk3588 family config itself. If that
# ever stops being true the whole derivation moves to the common include and
# every value below has to be re-read from there instead.
echo
echo "Family config delegation"
if grep -qE '^[[:space:]]*vendor\)' "${tmp}/rockchip-rk3588.conf"; then
	echo "  ok    rockchip-rk3588.conf handles 'vendor' in its own case \$BRANCH"
else
	echo "  DRIFT rockchip-rk3588.conf no longer has a vendor) case." >&2
	echo "        kernel-pin.env's derivation assumes it DOES. Re-read it." >&2
	status=1
fi

echo
echo "BRANCH=${ARMBIAN_BRANCH} mapping (rockchip-rk3588.conf)"
vendor_block="$(awk '/^[[:space:]]*vendor\)/{f=1} f{print} f&&/;;/{exit}' \
	"${tmp}/rockchip-rk3588.conf")"

mm="$(sed -n 's/.*KERNEL_MAJOR_MINOR="\([^"]*\)".*/\1/p' <<<"${vendor_block}" | head -1)"
lf="$(sed -n "s/.*LINUXFAMILY=\([A-Za-z0-9_]*\).*/\1/p"  <<<"${vendor_block}" | head -1)"
ks="$(sed -n "s/.*KERNELSOURCE='\([^']*\)'.*/\1/p"        <<<"${vendor_block}" | head -1)"
kb="$(sed -n "s/.*KERNELBRANCH='\([^']*\)'.*/\1/p"        <<<"${vendor_block}" | head -1)"
kp="$(sed -n "s/.*KERNELPATCHDIR='\([^']*\)'.*/\1/p"      <<<"${vendor_block}" | head -1)"

check "KERNEL_MAJOR_MINOR" "${KERNEL_MAJOR_MINOR}"    "${mm}"
check "LINUXFAMILY"        "${LINUXFAMILY}"           "${lf}"
check "KERNELSOURCE"       "${KERNELSOURCE}"          "${ks}"
check "KERNELBRANCH"       "${KERNELBRANCH_ARMBIAN}"  "${kb}"
check "KERNELPATCHDIR"     "${KERNELPATCHDIR}"        "${kp}"

# The rkr5.1 -> rkr6.1 trap, asserted rather than trusted.
if [[ "${kb}" == *"${KERNELBRANCH_NOT}"* ]]; then
	echo "  DRIFT vendor now resolves to ${KERNELBRANCH_NOT}, a DIFFERENT branch." >&2
	echo "        It is not an alias of ${KERNEL_BRANCH}; it produces a different" >&2
	echo "        kernel version. The pinned base commit is not on it." >&2
	status=1
fi

# --- LINUXCONFIG fallback ----------------------------------------------------
# The vendor) arm sets no LINUXCONFIG, so it comes from common.conf's default.
echo
echo "LINUXCONFIG fallback (common.conf)"
if grep -q 'LINUXCONFIG="linux-${LINUXFAMILY}-${BRANCH}"' "${tmp}/common.conf"; then
	check "LINUXCONFIG" "${LINUXCONFIG}" "linux-${lf}-${ARMBIAN_BRANCH}"
else
	echo "  DRIFT common.conf no longer defaults LINUXCONFIG to linux-<family>-<branch>" >&2
	status=1
fi

# --- the pinned base commit is still on the branch ---------------------------
echo
echo "Pinned base commit"
if curl -fsSL "${AUTH[@]}" \
	"${KERNEL_API}/compare/${KERNEL_BRANCH}...${KERNEL_COMMIT}" \
	-o "${tmp}/compare.json" 2>/dev/null; then
	cmp_status="$(sed -n 's/.*"status": *"\([a-z]*\)".*/\1/p' "${tmp}/compare.json" | head -1)"
	case "${cmp_status}" in
		behind | identical)
			printf '  ok    %-26s %s (%s branch tip)\n' \
				"${KERNEL_COMMIT:0:12}" "on ${KERNEL_BRANCH}" "${cmp_status}"
			;;
		*)
			echo "  DRIFT ${KERNEL_COMMIT} is '${cmp_status}' relative to ${KERNEL_BRANCH}." >&2
			echo "        A force-push or branch rename would do that. Re-pin deliberately." >&2
			status=1
			;;
	esac
else
	echo "  NOTE  could not reach api.github.com to verify the base commit"
fi

# --- the patch source is an OPEN pull request --------------------------------
echo
echo "Patch source (armbian/linux-rockchip PR #${UPSTREAM_PATCHES_PR})"
if curl -fsSL "${AUTH[@]}" \
	"${KERNEL_API}/pulls/${UPSTREAM_PATCHES_PR}" -o "${tmp}/pr.json" 2>/dev/null; then
	# python3 is already a hard dependency of this repo (build-series.py), and
	# `"ref"` appears twice in a PR payload — head first, then base. Grepping for
	# it would silently report the wrong one the day GitHub reorders the object.
	pr_state="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["state"])' \
		"${tmp}/pr.json")"
	pr_base="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["base"]["ref"])' \
		"${tmp}/pr.json")"
	if [[ "${pr_state}" == "${UPSTREAM_PATCHES_PR_STATE}" ]]; then
		printf '  ok    %-26s %s\n' "PR state" "${pr_state} (as pinned)"
	else
		echo "  NOTE  PR #${UPSTREAM_PATCHES_PR} is now '${pr_state}', not" >&2
		echo "        '${UPSTREAM_PATCHES_PR_STATE}'. If it MERGED, the fix is in the BSP" >&2
		echo "        branch itself: re-pin to a post-merge commit and retire this repo" >&2
		echo "        rather than double-applying. If it CLOSED unmerged, the series is" >&2
		echo "        now unmaintained upstream — decide whether to keep carrying it." >&2
		echo "        Update UPSTREAM_PATCHES_PR_STATE and docs/PROVENANCE.md together." >&2
		status=1
	fi
	[[ -n "${pr_base}" ]] && printf '  info  %-26s %s\n' "PR base branch" "${pr_base}"
	echo "  note  the series is pinned by COMMIT SHA, so a force-push of the PR"
	echo "        branch cannot change what this repo applies."
else
	echo "  NOTE  could not reach api.github.com to check the PR state"
fi

echo
if (( status == 0 )); then
	echo "PREFLIGHT OK — kernel-pin.env matches armbian/build @ ${rev}"
else
	echo "PREFLIGHT DRIFT — kernel-pin.env is stale for armbian/build @ ${rev}" >&2
	echo "Update kernel-pin.env and docs/PREFLIGHT.md together, then re-run." >&2
fi
exit "${status}"
