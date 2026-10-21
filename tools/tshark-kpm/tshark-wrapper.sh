#!/bin/bash
# Installed as /usr/local/bin/tshark (ahead of /usr/bin in PATH): runs tshark
# from the tshark-kpm image with /home and /tmp mounted at the same paths, so
# callers keep their pcap paths, flags and stdout unchanged.
d=docker
docker info >/dev/null 2>&1 || d="sudo -n docker"
exec $d run --rm -i --network none --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v /home:/home -v /tmp:/tmp -w "$PWD" tshark-kpm:trixie "$@"
