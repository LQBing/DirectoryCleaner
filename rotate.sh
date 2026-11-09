#!/bin/sh

# Rotate regular files under ROTATEPATH, or CLEANPATH when ROTATEPATH is empty.
# Rotation is opt-in through ROTATE=true.

case "$(printf '%s' "${ROTATE:-false}" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|on) ;;
    *) exit 0 ;;
esac

expand_paths() {
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        case "$path" in
            *'*'*|*'?'*|*'['*)
                for expanded in $path; do
                    printf '%s\n' "$expanded"
                done
                ;;
            *)
                printf '%s\n' "$path"
                ;;
        esac
    done
}

if [ -z "$ROTATEPATH" ]; then
    ROTATEPATH="$CLEANPATH"
fi
if [ -z "$ROTATEPATH" ]; then
    echo "ROTATEPATH and CLEANPATH empty"
    exit 0
fi

ROTATESIZE=${ROTATESIZE:-50M}
ROTATECOUNT=${ROTATECOUNT:-5}
ROTATECREATE=${ROTATECREATE:-}
case "$(printf '%s' "${ROTATEMODE:-copytruncate}" | tr '[:upper:]' '[:lower:]')" in
    create|copytruncate) ROTATEMODE="$(printf '%s' "${ROTATEMODE:-copytruncate}" | tr '[:upper:]' '[:lower:]')" ;;
    *)
        echo "ROTATEMODE must be create or copytruncate: $ROTATEMODE"
        exit 1
        ;;
esac
case "$(printf '%s' "${ROTATEINTERVAL:-off}" | tr '[:upper:]' '[:lower:]')" in
    off|hourly|daily|weekly|monthly|yearly|hour|day|week|month|year) ROTATEINTERVAL="$(printf '%s' "${ROTATEINTERVAL:-off}" | tr '[:upper:]' '[:lower:]')" ;;
    *)
        echo "ROTATEINTERVAL must be off, hourly, daily, weekly, monthly, or yearly"
        exit 1
        ;;
esac
case "$(printf '%s' "${ROTATECOMPRESS:-true}" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|on) compress=true ;;
    *) compress=false ;;
esac

interval_directive=""
case "$ROTATEINTERVAL" in
    off|"")
        interval_directive="size"
        ;;
    hourly|hour)
        interval_directive="hourly"
        ;;
    daily|day)
        interval_directive="daily"
        ;;
    weekly|week)
        interval_directive="weekly"
        ;;
    monthly|month)
        interval_directive="monthly"
        ;;
    yearly|year)
        interval_directive="yearly"
        ;;
    *)
        echo "ROTATEINTERVAL must be off, hourly, daily, weekly, monthly, or yearly"
        exit 1
        ;;
esac

case "$ROTATECOUNT" in
    ''|*[!0-9]*)
        echo "ROTATECOUNT must be a non-negative integer: $ROTATECOUNT"
        exit 1
        ;;
esac
size_value=$ROTATESIZE
case "$ROTATESIZE" in
    *k|*K|*M|*G)
        size_value=${ROTATESIZE%?}
        ;;
esac
case "$size_value" in
    ''|*[!0-9]*)
        echo "ROTATESIZE must be an integer optionally followed by k, K, M, or G: $ROTATESIZE"
        exit 1
        ;;
esac

LOCKWAIT=${LOCKWAIT:-120}
LOCK_FILE=/tmp/directorycleaner.run.lock
exec 9>"$LOCK_FILE"
if ! timeout "$LOCKWAIT" flock 9; then
    echo "rotate: timed out waiting for clean/rotate lock, skip"
    exit 1
fi

FILES=$(mktemp)
CONFIG=$(mktemp)
FIND_ERR=$(mktemp)
ROTATE_PATHS=$(mktemp)
STATE=${ROTATESTATE:-/var/lib/directorycleaner/logrotate.status}
STATE_DIR="$(dirname "$STATE")"
mkdir -p "$STATE_DIR" 2>/dev/null || true
trap 'rm -f "$FILES" "$CONFIG" "$FIND_ERR" "$ROTATE_PATHS"' 0 1 2 3 15

printf '%s\n' "$ROTATEPATH" | tr ';' '\n' | expand_paths > "$ROTATE_PATHS"
scan_failed=false
while IFS= read -r x; do
    [ -n "$x" ] || continue
    if [ -d "$x" ]; then
        if ! find "$x" -type f >>"$FILES" 2>"$FIND_ERR"; then
            echo "rotate: failed to scan $x"
            [ -s "$FIND_ERR" ] && cat "$FIND_ERR"
            scan_failed=true
        fi
    elif [ -f "$x" ]; then
        printf '%s\n' "$x" >>"$FILES"
    else
        echo "rotate: $x not exist, skip"
    fi
done < "$ROTATE_PATHS"
if [ -s "$FILES" ]; then
    sort -u "$FILES" -o "$FILES"
fi

count=0
while IFS= read -r file; do
    [ -n "$file" ] || continue
    if [ "$file" = "$LOCK_FILE" ] || [ "$file" = "$STATE" ]; then
        continue
    fi
    case "$file" in
        *.gz|*.xz|*.bz2|*.zip|*.zst|*.tgz|*.[0-9]|*.[0-9][0-9])
            continue
            ;;
    esac
    case "$file" in
        *'"'*|*'['*|*']'*)
            echo "rotate: skip filename containing a logrotate meta character: $file"
            continue
            ;;
    esac

    {
        printf '"%s" {\n' "$file"
        if [ "$interval_directive" = "size" ]; then
            printf '    size %s\n' "$ROTATESIZE"
        else
            printf '    %s\n' "$interval_directive"
            printf '    maxsize %s\n' "$ROTATESIZE"
        fi
        printf '    rotate %s\n' "$ROTATECOUNT"
        printf '    missingok\n'
        printf '    notifempty\n'
        printf '    su root root\n'
        if [ "$compress" = true ]; then
            printf '    compress\n'
            printf '    delaycompress\n'
        fi
        if [ "$ROTATEMODE" = copytruncate ]; then
            printf '    copytruncate\n'
        elif [ -n "$ROTATECREATE" ]; then
            printf '    create %s\n' "$ROTATECREATE"
        else
            printf '    create\n'
        fi
        printf '}\n\n'
    } >> "$CONFIG"
    count=$((count + 1))
done < "$FILES"

if [ "$count" -eq 0 ]; then
    echo "rotate: 0 candidates"
    if [ "$scan_failed" = true ]; then
        exit 1
    fi
    exit 0
fi

echo "rotate: $count candidates, interval=$ROTATEINTERVAL, size=$ROTATESIZE, rotate=$ROTATECOUNT, mode=$ROTATEMODE, compress=$compress"
if ! logrotate -s "$STATE" "$CONFIG"; then
    echo "rotate: logrotate reported errors"
    exit 1
fi
if [ "$scan_failed" = true ]; then
    echo "rotate: some paths were not fully scanned"
    exit 1
fi
exit 0
