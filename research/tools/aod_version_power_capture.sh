#!/bin/sh
# Finite, read-only capture; caller must establish an uninterrupted AOD phase.
set -eu
tag=${1:?usage: capture.sh phase-tag}
case "$tag" in ''|*[!a-zA-Z0-9_.-]*) exit 2;; esac
[ ${#tag} -le 48 ] || exit 2
base=/tmp/nnp-version-power-$tag
[ ! -e "$base-samples.jsonl" ] && [ ! -e "$base-checks.jsonl" ] || exit 3
[ -x /tmp/nnp-power-probe ] || exit 4
diag=/var/mobile/Library/Preferences/com.user.notchnowplaying.diagnostics.plist
number() {
    value=$(plutil -key "$1" "$diag" 2>/dev/null) || value=
    case "$value" in ''|*[!0-9.eE+-]*) printf null;; *) printf '%s' "$value";; esac
}
for key in Phase7AODPresentationActive LogicalLockState Phase7FixedBrightnessActive; do
    [ "$(number "$key")" = 1 ] || { printf 'Not ready: %s\n' "$key" >&2; exit 6; }
done
for key in PocketUISuspended MengoTicketOpen; do
    [ "$(number "$key")" = 0 ] || { printf 'Not ready: %s\n' "$key" >&2; exit 6; }
done
/tmp/nnp-power-probe 91 10 > "$base-samples.jsonl" 2> "$base-error.txt" &
sampler=$!
trap 'kill "$sampler" 2>/dev/null || true' EXIT
trap 'exit 130' HUP INT TERM
i=0
while [ "$i" -lt 91 ]; do
    stamp=$(date +%s)
    version=$(dpkg-query -W -f='${Version}' com.user.notchnowplaying)
    case "$version" in ''|*[!0-9.]*) exit 5;; esac
    pid=$(launchctl list | awk '$3 == "com.apple.SpringBoard" {print $1}')
    case "$pid" in ''|*[!0-9]*) pid=null;; esac
    printf '{"unix_time":%s,"version":"%s","SpringBoardPID":%s' "$stamp" "$version" "$pid" >> "$base-checks.jsonl"
    for key in DiagnosticFlushPID DiagnosticFlushBatchCount Phase7AODPresentationActive LogicalLockState \
        AODAmbientSensorActive Phase7FixedBrightnessActive Phase7FixedBrightnessPID Phase7FixedBrightnessAppliedNits \
        MengoNativeSensorPolicyActive MengoTicketOpen PocketUISuspended; do
        printf ',"%s":%s' "$key" "$(number "$key")" >> "$base-checks.jsonl"
    done
    printf '}\n' >> "$base-checks.jsonl"
    i=$((i + 1))
    [ "$i" -ge 91 ] || sleep 10
done
wait "$sampler"
trap - EXIT HUP INT TERM
printf 'COMPLETE %s\n' "$base"
