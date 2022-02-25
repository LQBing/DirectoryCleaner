FROM alpine
COPY cleaner.sh /usr/bin/cleaner
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/bin/cleaner
ENTRYPOINT [ "/bin/ash", "entrypoint.sh"]
