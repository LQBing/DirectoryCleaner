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
CROND=$(grep -n cleaner /var/spool/cron/crontabs/root)
if [ -z "$CRON" ]; then
    cleaner
elif [ -z "$CROND" ]; then
    echo "add cron record $CRON /usr/bin/cleaner"
    echo "$CRON /usr/bin/cleaner" >>/var/spool/cron/crontabs/root
    crond -f
else
    echo "skip add cron record"
    crond -f
fi
