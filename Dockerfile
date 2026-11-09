FROM alpine
RUN apk add --no-cache logrotate gzip \
    && mkdir -p /var/lib/directorycleaner
COPY cleaner.sh /usr/bin/cleaner
COPY rotate.sh /usr/bin/rotate
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/bin/cleaner /usr/bin/rotate
ENTRYPOINT [ "/bin/ash", "entrypoint.sh"]
