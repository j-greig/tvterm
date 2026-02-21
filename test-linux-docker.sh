#!/usr/bin/env bash
# Run tvterm interactively inside a Linux Docker container.
# Usage: bash test-linux-docker.sh
#
# Once inside the container you'll get a bash prompt.
# Run:   ./build-linux/tvterm

docker run --rm -it \
  -v "$(cd "$(dirname "$0")" && pwd)":/src \
  -w /src \
  ubuntu:22.04 \
  bash -c '
    apt-get update -qq
    apt-get install -y -qq libncursesw5 bash > /dev/null 2>&1
    export TERM=xterm-256color
    echo ""
    echo "=== Linux test container ready ==="
    echo "Run:  ./build-linux/tvterm"
    echo ""
    exec bash
  '
