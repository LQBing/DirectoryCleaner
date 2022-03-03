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
if [ -z "$KEEP" ]; then
    KEEP=30
fi
if [ -z "$CLEANPATH" ]; then
    echo "CLEANPATH empty"
    exit 0
fi
paths=$(echo "$CLEANPATH" | tr ";" "\n")
for x in $paths; do
    if [ ! -d "$x" ] && [ ! -f "$x" ]; then
        echo "$x not exist,exit."
        mkdir -p "$x"
    fi
done

date
for x in $paths; do
    echo "clean files $KEEP days ago in [$x]"
    find "$x" -type f -mtime +$KEEP
    find "$x" -type f -mtime +$KEEP -delete
    if [ -z "$CLEANEMPTYFOLDER" ]; then
        find "$x" -type d -mtime +$KEEP -empty
        find "$x" -type d -mtime +$KEEP -empty -delete
        mkdir -p "$x"
    fi
done
