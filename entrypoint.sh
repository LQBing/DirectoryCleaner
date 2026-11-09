#!/bin/sh
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

cron_field_count() {
    printf '%s\n' "$1" | wc -w | tr -d ' '
}

if [ -n "$KEEPPATH" ]; then
    printf '%s\n' "$KEEPPATH" | tr ";" "\n" | expand_paths | while IFS= read -r x; do
        if [ ! -d "$x" ] && [ ! -f "$x" ]; then
            echo "$x not exist, create it"
            mkdir -p "$x"
        fi
    done
fi
if [ -z "$CLEANPATH" ]; then
    echo "CLEANPATH empty"
    exit 0
fi

PATHS=$(mktemp)
trap 'rm -f "$PATHS"' 0 1 2 3 15
printf '%s\n' "$CLEANPATH" | tr ";" "\n" | expand_paths > "$PATHS"
while IFS= read -r x; do
    [ -n "$x" ] || continue
    if [ ! -d "$x" ] && [ ! -f "$x" ]; then
        echo "[error] $x not exist, exit"
        exit 0
    fi
done < "$PATHS"
case "$(printf '%s' "${ROTATE:-false}" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|on) rotate_enabled=true ;;
    *) rotate_enabled=false ;;
esac

if [ -z "$CRON" ]; then
    if [ -n "$ROTATECRON" ] && [ "$rotate_enabled" = true ]; then
        echo "CRON empty, run once; ROTATECRON ignored"
    fi
    if [ "$rotate_enabled" = true ]; then
        /usr/bin/rotate
    fi
    cleaner
    exit 0
fi

if [ "$(cron_field_count "$CRON")" -ne 5 ]; then
    echo "CRON must have exactly 5 fields: $CRON"
    exit 1
fi
if [ "$rotate_enabled" = true ]; then
    if [ -z "$ROTATECRON" ]; then
        ROTATECRON="$CRON"
    fi
    if [ "$(cron_field_count "$ROTATECRON")" -ne 5 ]; then
        echo "ROTATECRON must have exactly 5 fields: $ROTATECRON"
        exit 1
    fi
fi

CRON_FILE=/var/spool/cron/crontabs/root
mkdir -p "$(dirname "$CRON_FILE")"
touch "$CRON_FILE"

CRON_TMP=$(mktemp)
grep -v -e '/usr/bin/cleaner[[:space:]]*$' -e '/usr/bin/rotate[[:space:]]*$' "$CRON_FILE" > "$CRON_TMP" || true
echo "$CRON /usr/bin/cleaner" >> "$CRON_TMP"
if [ "$rotate_enabled" = true ]; then
    echo "$ROTATECRON /usr/bin/rotate" >> "$CRON_TMP"
fi
cat "$CRON_TMP" > "$CRON_FILE"
rm -f "$CRON_TMP"
chmod 600 "$CRON_FILE" 2>/dev/null || true

echo "updated cron records for cleaner"
if [ "$rotate_enabled" = true ]; then
    echo "updated cron records for rotate"
else
    echo "skipped cron record for rotate (ROTATE disabled)"
fi

crond -f
