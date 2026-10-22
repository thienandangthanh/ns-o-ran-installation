# rc-decode: an E2SM-RC v2.0 wire decoder independent of the agents' codec.
# Generator asn1c mouse07410@584d86e (built at -O0: newer GCCs miscompile it at
# -O2), schema = rc@a2282ee e2sm/e2sm-rc-2.0.asn + e2sm/e2sm-common.asn, the
# exact files the deployed rc xApp was generated from.
FROM ubuntu:24.04 AS build
RUN apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends \
        ca-certificates git build-essential autoconf automake libtool bison flex \
    && rm -rf /var/lib/apt/lists/*
ARG ASN1C_SHA=584d86e22d54d401c5d349128f28b0c41fae4d24
ARG RC_SHA=a2282eedc9e32f60298bf530456ad367bef0824b
RUN git clone -q https://github.com/mouse07410/asn1c.git /src/asn1c && git -C /src/asn1c checkout -q $ASN1C_SHA \
    && cd /src/asn1c && autoreconf -i >/dev/null 2>&1 \
    && ./configure -q --prefix=/opt/asn1c CFLAGS="-O0 -g -w -std=gnu11" >/dev/null \
    && make -j"$(nproc)" >/dev/null 2>&1 && make install >/dev/null
RUN git clone -q https://github.com/o-ran-sc/ric-app-rc.git /src/rc && git -C /src/rc checkout -q $RC_SHA \
    && test "$(git -C /src/rc rev-parse HEAD)" = "$RC_SHA"
WORKDIR /gen
RUN /opt/asn1c/bin/asn1c -pdu=auto -fincludes-quoted -fcompound-names -findirect-choice -fno-include-deps \
        -no-gen-example -gen-APER /src/rc/e2sm/e2sm-common.asn /src/rc/e2sm/e2sm-rc-2.0.asn >/gen.log 2>&1 \
    && ls *.c | wc -l
COPY rc-decode.c /gen/
RUN gcc -O1 -w -I. -DASN_PDU_COLLECTION -o /usr/local/bin/rc-decode *.c -lm

FROM ubuntu:24.04
COPY --from=build /usr/local/bin/rc-decode /usr/local/bin/rc-decode
ENTRYPOINT ["rc-decode"]
