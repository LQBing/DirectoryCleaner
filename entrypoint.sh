#!/bin/sh
if [ -n "$KEEPPATH" ]; then
    keeppaths=$(echo "$KEEPPATH" | tr ";" "\n")
    for x in $keeppaths; do
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
paths=$(echo "$CLEANPATH" | tr ";" "\n")
for x in $paths; do
    if [ ! -d "$x" ] && [ ! -f "$x" ]; then
        echo "[error] $x not exist, exit"
        exit 0
    fi
done
case "$ROTATE" in
    true|TRUE|1|yes|YES|on|ON) rotate_enabled=true ;;
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

CRON_FILE=/var/spool/cron/crontabs/root
mkdir -p "$(dirname "$CRON_FILE")"
touch "$CRON_FILE"

if ! grep -q '/usr/bin/cleaner' "$CRON_FILE"; then
    echo "add cron record $CRON /usr/bin/cleaner"
    echo "$CRON /usr/bin/cleaner" >>"$CRON_FILE"
else
    echo "skip add cron record for cleaner"
fi

if [ "$rotate_enabled" = true ]; then
    if [ -z "$ROTATECRON" ]; then
        ROTATECRON="$CRON"
    fi
    if ! grep -q '/usr/bin/rotate' "$CRON_FILE"; then
        echo "add cron record $ROTATECRON /usr/bin/rotate"
        echo "$ROTATECRON /usr/bin/rotate" >>"$CRON_FILE"
    else
        echo "skip add cron record for rotate"
    fi
else
    echo "skip add cron record for rotate (ROTATE disabled)"
fi

crond -f
