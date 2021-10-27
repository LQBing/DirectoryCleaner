if [ -z $CLEANPATH ]
then
echo "CLEANPATH can not be empty"
exit 0
fi
CROND=$(grep -n clean_directory /var/spool/cron/crontabs/root)
if [ -z $CRON ]
then
clean_directory
elif [ -z "$CROND" ]
then
echo "add cron recored $CRON /usr/bin/clean_directory"
echo "$CRON /usr/bin/clean_directory" >> /var/spool/cron/crontabs/root
crond -f
else
echo "skip cron recored"
crond -f
fi
