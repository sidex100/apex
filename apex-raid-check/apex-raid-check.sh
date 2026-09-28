#!/bin/bash
# apex-raid-check: mail when Dell PERC RAID / physical disk state changes.
#   ALERT - controller not Optimal, virtual drive not Optl, or physical drive not Onln (reminder every 12 h)
#   OK    - state is back to normal
#   INFO  - state lines changed while normal, or SAS "Non-medium error count" grew by more than NME_THRESHOLD
#           since the last report (each reboot adds ~3 per disk: controller reset, harmless)
# Disk SMART health/temperature is watched by smartd, not here.
# Installed as /usr/local/sbin/apex-raid-check, run hourly by apex-raid-check.timer.
set -u

PERCCLI=/opt/MegaRAID/perccli/perccli64
STATE_DIR=/var/lib/apex-raid-check
MAILTO=root
TAG="[$(hostname -s)]"
REMIND=$((12 * 3600))
# 2026-09-28: 10 -> 100: each reboot adds exactly 3 per disk, 10 fired after a few reboots; a bad cable/backplane gives hundreds
NME_THRESHOLD=100

now=$(date -u +%s)
send() { printf '%s\n' "$2" | mail -s "$TAG $1" "$MAILTO"; }

snapshot() {
    echo "controller: $($PERCCLI /c0 show all | awk -F' = ' '/^Controller Status/ {print $2}')"
    # DG/VD TYPE State ...
    $PERCCLI /c0/vall show | awk '/^[0-9]+\/[0-9]+ / {print "vd " $1 ": " $2 " " $3}'
    # EID:Slt DID State DG Size(2 fields) Intf Med ...
    $PERCCLI /c0/eall/sall show | awk '/^[0-9]+:[0-9]+ / {print "pd " $1 ": " $8 " " $3}'
}

nme_list() {
    for d in $(smartctl --scan | awk '/megaraid,/ {print $3}'); do
        v=$(smartctl -x -d "$d" /dev/bus/0 | awk -F: '/Non-medium error count/ {gsub(/ /, "", $2); print $2}')
        echo "$d ${v:-?}"
    done
}

cur=$(snapshot 2>&1)
nme=$(nme_list 2>&1)
bad=0
printf '%s\n' "$cur" | grep -q '^vd ' || bad=1
printf '%s\n' "$cur" | grep '^controller:' | grep -qv ': Optimal$' && bad=1
printf '%s\n' "$cur" | grep '^vd ' | grep -qv ' Optl$' && bad=1
printf '%s\n' "$cur" | grep -E '^pd [0-9]+:[0-9]+:' | grep -qv ' Onln$' && bad=1

report="Current state:
$cur

Non-medium error count (disk, value):
$nme

Details: $PERCCLI /c0 show all ; $PERCCLI /c0/eall/sall show"

first_run=0
[ -d "$STATE_DIR" ] || { mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"; first_run=1; }

if [ "$first_run" -eq 1 ]; then
    send "apex-raid-check started" "apex-raid-check is active (bad=$bad).

$report"
    [ "$bad" -eq 1 ] && echo "$now" > "$STATE_DIR/last_alert"
else
    # older versions kept non-medium lines in the state file - ignore them
    prev=$(grep -v 'non-medium' "$STATE_DIR/state" 2>/dev/null || true)
    prev_bad=$(cat "$STATE_DIR/bad" 2>/dev/null || echo 0)
    last_alert=$(cat "$STATE_DIR/last_alert" 2>/dev/null || echo 0)
    if [ "$cur" != "$prev" ]; then
        changes=$(diff <(printf '%s\n' "$prev") <(printf '%s\n' "$cur") | grep -E '^[<>]')
        if [ "$bad" -eq 1 ]; then
            send "ALERT: RAID not optimal" "RAID state changed and is NOT normal.

Changes (< old, > new):
$changes

$report"
            echo "$now" > "$STATE_DIR/last_alert"
        elif [ "$prev_bad" -eq 1 ]; then
            send "OK: RAID back to normal" "Changes (< old, > new):
$changes

$report"
        else
            send "INFO: RAID state lines changed" "Changes (< old, > new):
$changes

$report"
        fi
    elif [ "$bad" -eq 1 ] && [ $((now - last_alert)) -ge "$REMIND" ]; then
        send "ALERT (reminder): RAID still not optimal" "$report"
        echo "$now" > "$STATE_DIR/last_alert"
    fi
fi

# Non-medium error count: report only real growth (baseline = value at last report).
grown=""
while read -r d v; do
    [ -n "$d" ] || continue
    case "$v" in ''|*[!0-9]*) continue ;; esac
    f="$STATE_DIR/nme-${d//[^A-Za-z0-9]/_}"
    base=$(cat "$f" 2>/dev/null || true)
    if [ -z "$base" ] || [ "$v" -lt "$base" ]; then
        echo "$v" > "$f"                                # first run or disk replaced
    elif [ $((v - base)) -gt "$NME_THRESHOLD" ]; then
        grown="$grown$d: $base -> $v (+$((v - base)))
"
        echo "$v" > "$f"
    fi
done <<< "$nme"
if [ -n "$grown" ]; then
    send "INFO: disk non-medium errors grew" "Non-medium error count grew by more than $NME_THRESHOLD since last report:
$grown
(each reboot adds ~3 per disk - controller reset; steady growth without reboots = check controller/cables/backplane)

$report"
fi

printf '%s\n' "$cur" > "$STATE_DIR/state"
echo "$bad" > "$STATE_DIR/bad"
