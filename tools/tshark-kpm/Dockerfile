# tshark >= 4.4 for E2SM-KPM evidence. Ubuntu 24.04 ships tshark 4.2.2, whose
# KPM dissector throws "Malformed Packet" (epan/asn1.c:232) on REAL records;
# Debian 13 (trixie) ships 4.4.x, which decodes them cleanly. Built from
# Debian's own archive (the Launchpad wireshark PPA was returning 503s).
FROM debian:trixie-slim
RUN echo "wireshark-common wireshark-common/install-setuid boolean false" | debconf-set-selections \
    && apt-get update -q \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends tshark \
    && rm -rf /var/lib/apt/lists/*
ENTRYPOINT ["tshark"]
