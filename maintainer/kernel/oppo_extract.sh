#!/bin/bash
# Extract OPPO's sched_assist family (UX threads, binder/locking inheritance, IM flags, audio UX, frame boost) from OPPO's
# own sm8250 4.19 kernel as a clean patch for a Qualcomm 4.19 WALT tree (Lineage lineage-24.0 + pipa).
#   bash maintainer/kernel/oppo_extract.sh <oppo-kernel-tree> <our-tree> <out.patch> [file...]
# For every hooked file, unifdef removes every other OPPO feature (-U), once with and once without the wanted ones; the
# diff between the two is only the wanted hooks, in OPPO's context. Apply with `patch -p1 -F1` (fuzz 2+ misplaces hunks
# in fair.c) or better 3-way: KEEP=<dir> saves both versions; `git merge-file <ours> <dir>/a/<f> <dir>/b/<f>` per file.
# "OPPO feature" = an OPLUS_*/VENDOR_EDIT macro, or a CONFIG_ symbol no Kconfig of <our-tree> defines (e.g.
# CONFIG_LOCKING_PROTECT, CONFIG_SCHED_WALT_COBUCK), so plain upstream/QCOM #ifdefs are left alone.
# Source: github.com/oppo-source/android_kernel_oppo_sm8250 branch oppo/sm8250_u_14.0.0_oslo (OPD2101 = OPPO Pad,
# SD870, ColorOS 14, 4.19.157); module sources: android_kernel_modules_and_devicetree_oppo_sm8250, same branch,
# vendor/oplus/kernel/oplus_performance/{sched_assist,frame_boost,im}. Feature set = OPPO's kona-perf_defconfig minus
# stats/IO/memory features. Needs unifdef (build it: gcc -std=gnu11 -O2 -o unifdef <tree>/scripts/unifdef.c).
set -euo pipefail
SRC=$(realpath "${1:?oppo tree}"); OURS=$(realpath "${2:?our tree}"); OUT=$(realpath -m "${3:?out.patch}"); shift 3
UNIFDEF=${UNIFDEF:-unifdef}
WANT=${WANT:-'OPLUS_FEATURE_SCHED_ASSIST CONFIG_OPLUS_FEATURE_SCHED_ASSIST CONFIG_OPLUS_FEATURE_SCHED_UX_PRIORITY
CONFIG_OPLUS_UX_IM_FLAG OPLUS_FEATURE_IM CONFIG_OPLUS_FEATURE_IM CONFIG_OPLUS_LOCKING_STRATEGY CONFIG_OPLUS_LOCKING_OSQ
CONFIG_LOCKING_PROTECT CONFIG_OPLUS_FEATURE_FRAME_BOOST CONFIG_OPLUS_CPU_AUDIO_PERF CONFIG_OPLUS_FEATURE_AUDIO_OPT'}
FILES=${*:-kernel/sched/fair.c kernel/sched/core.c kernel/sched/sched.h kernel/sched/rt.c kernel/sched/cpupri.c
kernel/sched/cputime.c kernel/sched/topology.c kernel/sched/walt.c kernel/sched/cpufreq_schedutil.c kernel/locking/rwsem.c
kernel/locking/rwsem-xadd.c kernel/locking/rwsem.h kernel/locking/mutex.c kernel/locking/rtmutex.c
kernel/locking/percpu-rwsem.c kernel/futex.c kernel/workqueue.c kernel/fork.c kernel/signal.c kernel/sysctl.c kernel/cpu.c
kernel/Makefile kernel/Kconfig.locks fs/proc/base.c fs/exec.c drivers/android/binder.c drivers/android/binder_internal.h
drivers/cpufreq/cpufreq.c include/linux/sched.h include/linux/sched/sysctl.h include/linux/sched/cpufreq.h
include/linux/rwsem.h include/linux/percpu-rwsem.h include/linux/mutex.h include/linux/workqueue.h
include/trace/events/sched.h}
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
KEEP=${KEEP:-}    # KEEP=<dir>: also save a/ (OPPO without the features) and b/ (with) there, for `git merge-file`
# every CONFIG_ symbol our tree knows
find "$OURS" -name 'Kconfig*' -not -path '*/out/*' -print0 | xargs -0 grep -ohE '^\s*(menu)?config\s+[A-Za-z0-9_]+' |
	awk '{print "CONFIG_"$NF}' | sort -u > "$w/ours"
tr ' \n' '\n\n' <<<"$WANT" | sed '/^$/d' | sort -u > "$w/want"
: > "$OUT"
for f in $FILES; do
	[ -f "$SRC/$f" ] || { echo "skip $f (not in the OPPO tree)" >&2; continue; }
	mkdir -p "$w/in/$(dirname "$f")"
	cp "$SRC/$f" "$w/in/$f"
	grep -hE '^\s*#\s*(if|ifdef|ifndef|elif)\b' "$SRC/$f" | grep -oE '\b(CONFIG_[A-Za-z0-9_]+|OPLUS_[A-Z0-9_]+|VENDOR_EDIT)\b' |
		sort -u > "$w/syms" || true
	{ grep -vE '^CONFIG_' "$w/syms" || true; grep -E '^CONFIG_' "$w/syms" | comm -23 - "$w/ours" || true; } |
		sort -u | comm -23 - "$w/want" > "$w/others"
	# unifdef does not evaluate IS_ENABLED()/IS_BUILTIN(): rewrite them to defined() for OPPO symbols only
	cat "$w/others" "$w/want" | awk '{printf "s#IS_(ENABLED|BUILTIN)\\(%s\\)#defined(%s)#g\n", $1, $1}' > "$w/isen.sed"
	sed -E -i -f "$w/isen.sed" "$w/in/$f"
	uo=(); while read -r m; do uo+=("-U$m"); done < "$w/others"
	uw=(); while read -r m; do uw+=("-U$m"); done < "$w/want"
	mkdir -p "$w/a/$(dirname "$f")" "$w/b/$(dirname "$f")"
	t=(); case $f in *.c|*.h) ;; *) t=(-t);; esac    # Makefile/Kconfig: plain text, no C comment/quote parsing
	"$UNIFDEF" "${t[@]}" -B "${uo[@]}" "${uw[@]}" "$w/in/$f" > "$w/a/$f" || true    # exit 1 = file changed, fine
	"$UNIFDEF" "${t[@]}" -B "${uo[@]}" "$w/in/$f" > "$w/b/$f" || true
	(cd "$w" && diff -u "a/$f" "b/$f" || true) >> "$OUT"
	echo "$f: $(cd "$w" && diff -u "a/$f" "b/$f" | grep -c '^+[^+]' || true) lines added" >&2
done
grep -c '^+++ ' "$OUT" | sed 's/^/files in patch: /' >&2
[ -z "$KEEP" ] || { rm -rf "$KEEP"; mkdir -p "$KEEP"; cp -a "$w/a" "$w/b" "$KEEP/"; }
