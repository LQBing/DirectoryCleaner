FROM alpine
COPY cleaner.sh /usr/bin/clean_directory
RUN chmod +x /usr/bin/clean_directory
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT [ "sh", "entrypoint.sh"]