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

if [ -n "$KEEPPATH" ]; then
    printf '%s\n' "$KEEPPATH" | tr ";" "\n" | expand_paths | while IFS= read -r x; do
        if [ ! -d "$x" ] && [ ! -f "$x" ]; then
            echo "$x not exist, create it"
            mkdir -p "$x"
        fi
    done
fi
if [ -z "$KEEP" ]; then
    KEEP=30
fi
case "$(printf '%s' "${CLEANEMPTYFOLDER:-true}" | tr '[:upper:]' '[:lower:]')" in
    false|0|no|off) clean_empty=false ;;
    *) clean_empty=true ;;
esac
if [ -z "$CLEANPATH" ]; then
    echo "CLEANPATH empty"
    exit 0
fi

LOCKWAIT=${LOCKWAIT:-120}
LOCK_FILE=/tmp/directorycleaner.run.lock
exec 9>"$LOCK_FILE"
if ! timeout "$LOCKWAIT" flock 9; then
    echo "clean: timed out waiting for clean/rotate lock, skip"
    exit 1
fi

PATHS=$(mktemp)
trap 'rm -f "$PATHS"' 0 1 2 3 15
printf '%s\n' "$CLEANPATH" | tr ";" "\n" | expand_paths > "$PATHS"

while IFS= read -r x; do
    [ -n "$x" ] || continue
    if [ ! -d "$x" ] && [ ! -f "$x" ]; then
        echo "$x not exist,exit."
        mkdir -p "$x"
    fi
done < "$PATHS"

date
while IFS= read -r x; do
    [ -n "$x" ] || continue
    echo "clean files $KEEP days ago in [$x]"
    find "$x" -type f -mtime +"$KEEP"
    find "$x" -type f -mtime +"$KEEP" -delete
    if [ -d "$x" ] && [ "$clean_empty" = true ]; then
        find "$x" -type d -mtime +"$KEEP" -empty
        find "$x" -type d -mtime +"$KEEP" -empty -delete
        mkdir -p "$x"
    fi
done < "$PATHS"
