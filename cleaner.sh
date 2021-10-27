if [ -z "$KEEP" ]
then
KEEP=30
fi
if [ -z "$CLEANPATH" ]
then
echo "CLEANPATH can not empty"
exit 0
fi

paths=$(echo $CLEANPATH | tr ";" "\n")
date
for x in $paths
do
    echo "clean files $KEEP days ago in [$x]"
    find $x -type f -mtime +$KEEP
    find $x -type f -mtime +$KEEP -delete
    find $x -empty -type d
    find $x -empty -type d -delete
    mkdir -p $x
done

