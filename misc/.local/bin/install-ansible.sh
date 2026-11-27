#!/bin/sh

set -e
set -u

exec uv tool install ansible-dev-tools \
    --force \
    --with-executables-from ansible-builder \
    --with-executables-from ansible-core \
    --with-executables-from ansible-creator \
    --with-executables-from ansible-dev-environment \
    --with-executables-from ansible-lint \
    --with-executables-from ansible-navigator \
    --with-executables-from ansible-sign \
    --with-executables-from molecule \
    --with 'molecule-plugins[docker]' \
    --with 'molecule-plugins[podman]' \
    --with ansible \
    --with boto3 \
    --with google-auth \
    --with proxmoxer \
    --with requests \
    --with netaddr
