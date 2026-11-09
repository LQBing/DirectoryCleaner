#!/bin/sh

# Rotate every regular file collected by CLEANPATH, or ROTATEPATH when set.
# Rotation is opt-in through ROTATE=true.
case "${ROTATE:-false}" in
    true|TRUE|1|yes|YES|on|ON) ;;
    *) exit 0 ;;
esac

if [ -z "$ROTATEPATH" ]; then
    ROTATEPATH="$CLEANPATH"
fi
if [ -z "$ROTATEPATH" ]; then
    echo "ROTATEPATH and CLEANPATH empty"
    exit 0
fi

ROTATESIZE=${ROTATESIZE:-50M}
ROTATECOUNT=${ROTATECOUNT:-5}
ROTATEMODE=${ROTATEMODE:-create}
ROTATECOMPRESS=${ROTATECOMPRESS:-true}

case "$ROTATECOUNT" in
    ''|*[!0-9]*)
        echo "ROTATECOUNT must be a non-negative integer: $ROTATECOUNT"
        exit 1
        ;;
esac
case "$ROTATEMODE" in
    create|copytruncate) ;;
    *)
        echo "ROTATEMODE must be create or copytruncate: $ROTATEMODE"
        exit 1
        ;;
esac
case "$ROTATECOMPRESS" in
    true|TRUE|1|yes|YES|on|ON) compress=true ;;
    *) compress=false ;;
esac

FILES=$(mktemp)
CONFIG=$(mktemp)
STATE_DIR=/var/lib/logrotate
STATE="$STATE_DIR/directorycleaner.status"
trap 'rm -f "$FILES" "$CONFIG"' 0 1 2 3 15

paths=$(echo "$ROTATEPATH" | tr ";" "\n")
for x in $paths; do
    if [ -d "$x" ]; then
        find "$x" -type f 2>/dev/null
    elif [ -f "$x" ]; then
        printf '%s\n' "$x"
    else
        echo "rotate: $x not exist, skip"
    fi
done | sort -u > "$FILES"

count=0
while IFS= read -r file; do
    [ -n "$file" ] || continue
    case "$file" in
        *.gz|*.xz|*.bz2|*.zip|*.zst|*.tgz|*.[0-9]|*.[0-9][0-9])
            continue
            ;;
    esac
    case "$file" in
        *'"'*)
            echo "rotate: skip filename containing double quote: $file"
            continue
            ;;
    esac

    {
        printf '"%s" {\n' "$file"
        printf '    size %s\n' "$ROTATESIZE"
        printf '    rotate %s\n' "$ROTATECOUNT"
        printf '    missingok\n'
        printf '    notifempty\n'
        printf '    su root root\n'
        if [ "$compress" = true ]; then
            printf '    compress\n'
        fi
        if [ "$ROTATEMODE" = copytruncate ]; then
            printf '    copytruncate\n'
        else
            printf '    create\n'
        fi
        printf '}\n\n'
    } >> "$CONFIG"
    count=$((count + 1))
done < "$FILES"

if [ "$count" -eq 0 ]; then
    echo "rotate: no files found"
    exit 0
fi

mkdir -p "$STATE_DIR"
echo "rotate $count files, size=$ROTATESIZE, rotate=$ROTATECOUNT, mode=$ROTATEMODE, compress=$compress"
logrotate -s "$STATE" "$CONFIG"
