FROM alpine:3.20

# Install dependencies
ADD install.sh install.sh
RUN sh install.sh && rm install.sh

# Environment variables
ENV MONGO_HOST **None**
ENV MONGO_PORT 27017
ENV MONGO_USER **None**
ENV MONGO_PASSWORD **None**
ENV MONGO_AUTH_DB **None**
ENV MONGO_DATABASE **None**
ENV MULTI_FILES no
ENV MONGODUMP_EXTRA_OPTIONS ''
ENV S3_ACCESS_KEY_ID **None**
ENV S3_SECRET_ACCESS_KEY **None**
ENV S3_BUCKET **None**
ENV S3_REGION us-west-1
ENV S3_ENDPOINT **None**
ENV S3_S3V4 no
ENV S3_PREFIX 'backup_mongo'
ENV S3_FILENAME **None**
ENV S3_ENSURE_BUCKET_EXISTS yes
ENV S3_IAMROLE false
ENV SCHEDULE **None**

# Add ONLY the scripts you actually have
ADD run.sh /run.sh
ADD backup.sh /backup.sh

# Make executable
RUN chmod +x /run.sh /backup.sh && \
    rm -rf /tmp/* /var/cache/apk/* /root/.cache

CMD ["sh", "/run.sh"]