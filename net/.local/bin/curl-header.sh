#!/bin/sh

set -e
set -u

exec curl -sS --dump-header - --output /dev/null "$@"
