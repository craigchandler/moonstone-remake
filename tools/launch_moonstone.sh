#!/bin/sh
launcher_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
exec "$launcher_dir/@BINARY@" -- "$@"
