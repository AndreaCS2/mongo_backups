#!/bin/sh

# exit if a command fails
set -eo pipefail

apk update

# install mongodb-tools (includes mongodump, mongorestore, etc.)
# Compatible with MongoDB 4.4+ through MongoDB 8.0
apk add mongodb-tools

# install s3 tools
apk add python3 py3-pip
pip install awscli --break-system-packages

# cleanup
rm -rf /var/cache/apk/*
