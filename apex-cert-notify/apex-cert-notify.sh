#!/bin/bash
# apex-cert-notify: mail about nginx ACME certificates (nginx-module-acme has no notifications).
#   NEW     - certificate seen for the first time (new site / new name)
#   OK      - certificate was renewed (serial changed)
#   WARNING - planned renewal time + grace has passed and certificate is still the old one
#   ERROR   - new ACME lines (warn/error) in nginx error log
# Planned renewal (from module source): lifetime > 10 days -> at 2/3 of lifetime, else at 1/2.
# Installed as /usr/local/sbin/apex-cert-notify, run hourly by apex-cert-notify.timer.
set -u

CERT_GLOB='/var/cache/nginx/acme-letsencrypt*/*.crt'
STATE_DIR=/var/lib/apex-cert-notify
NGINX_LOG=/var/log/nginx/error.log
MAILTO=root
TAG="[$(hostname -s)]"
GRACE_LONG=$((3 * 86400))   # after planned renewal, certs > 10 days
GRACE_SHORT=$((24 * 3600))  # after planned renewal, certs <= 10 days

now=$(date -u +%s)
fmt() { date -u -d "@$1" '+%Y-%m-%d %H:%M UTC'; }
send() { printf '%s\n' "$2" | mail -s "$TAG $1" "$MAILTO"; }

first_run=0
[ -d "$STATE_DIR" ] || { mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"; first_run=1; }
summary=""

for crt in $CERT_GLOB; do
    [ -f "$crt" ] || continue
    base=$(basename "$crt" .crt)
    name=${base%-*}                                  # strip module hash suffix
    serial=$(openssl x509 -in "$crt" -noout -serial | cut -d= -f2)
    nb=$(date -u -d "$(openssl x509 -in "$crt" -noout -startdate | cut -d= -f2)" +%s)
    na=$(date -u -d "$(openssl x509 -in "$crt" -noout -enddate | cut -d= -f2)" +%s)
    life=$((na - nb))
    if [ "$life" -gt $((10 * 86400)) ]; then
        plan=$((nb + life * 2 / 3)); grace=$GRACE_LONG
    else
        plan=$((nb + life / 2)); grace=$GRACE_SHORT
    fi
    alert=$((plan + grace))
    info="$name
  valid:   $(fmt "$nb") -> $(fmt "$na")
  planned renewal: $(fmt "$plan")
  alert if not renewed by: $(fmt "$alert")
  serial:  $serial"
    summary="$summary$info
"

    state="$STATE_DIR/$(printf '%s' "$base" | tr -c 'A-Za-z0-9._-' '_')"
    old=$(cat "$state" 2>/dev/null || true)
    if [ -n "$old" ] && [ "$old" != "$serial" ]; then
        send "OK: certificate renewed for $name" "Certificate renewed.

$info"
    elif [ -z "$old" ] && [ "$first_run" -eq 0 ]; then
        send "NEW: certificate issued for $name" "New certificate appeared (new site or new name).

$info"
    fi
    printf '%s\n' "$serial" > "$state"

    if [ "$now" -gt "$alert" ]; then
        send "WARNING: certificate for $name not renewed" "Planned renewal time + grace has passed, certificate is still the old one.
Expires in $(( (na - now) / 3600 )) hours.

$info

Check: grep -i acme $NGINX_LOG | tail"
    fi
done

if [ "$first_run" -eq 1 ]; then
    send "apex-cert-notify started" "apex-cert-notify is active. Monitoring:

$summary"
fi

# New ACME warn/error lines in nginx error log since last run (handles daily rotation).
off_file="$STATE_DIR/nginx-error-log.offset"
off=$(cat "$off_file" 2>/dev/null || echo 0)
size=$(stat -c %s "$NGINX_LOG" 2>/dev/null || echo 0)
new=""
if [ "$size" -lt "$off" ]; then
    [ -f "$NGINX_LOG.1" ] && new=$(tail -c +"$((off + 1))" "$NGINX_LOG.1")
    off=0
fi
new="$new$(tail -c +"$((off + 1))" "$NGINX_LOG" 2>/dev/null)"
printf '%s\n' "$size" > "$off_file"
errs=$(printf '%s\n' "$new" | grep -i 'acme' | grep -E '\[(warn|error|crit|alert|emerg)\]' | tail -n 50)
if [ "$first_run" -eq 0 ] && [ -n "$errs" ]; then
    send "ERROR: ACME messages in nginx log" "New ACME warn/error lines in $NGINX_LOG:

$errs"
fi
