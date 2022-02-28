#!/bin/sh
if [ -z "$CLEANPATH" ]; then
    echo "CLEANPATH empty"
    exit 0
fi
paths=$(echo "$CLEANPATH" | tr ";" "\n")
for x in $paths; do
    if [ ! -d "$x" ] && [ ! -f "$x" ]; then
        echo "$x not exist"
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
