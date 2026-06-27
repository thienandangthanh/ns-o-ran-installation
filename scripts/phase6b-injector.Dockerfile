# Phase 6b Stage D (M-RC4) — in-cluster RMR injector image.
#
# Minimal Python + ricxappframe + librmr runtime used to push mock TS_QOE_PREDICTION
# (mtype 30002) messages to the live TS xApp. librmr_si.so is VENDORED from the running
# TS pod (exact testbed rmr 4.8.1) at build time rather than re-downloaded, so the
# wire-compat with TS is guaranteed and the build does not depend on packagecloud.
#
# Build context must contain librmr_si.so.4.8.1 (extracted from the TS pod). See
# phase6b-closed-loop-run.sh ensure_injector().
FROM python:3.11-slim

COPY librmr_si.so.4.8.1 /usr/local/lib/
RUN cd /usr/local/lib \
 && ln -sf librmr_si.so.4.8.1 librmr_si.so.4 \
 && ln -sf librmr_si.so.4 librmr_si.so \
 && ldconfig
ENV LD_LIBRARY_PATH=/usr/local/lib

# ricxappframe pulls ricsdl -> hiredis, whose pinned version builds from source on
# this base; gcc + libc6-dev let it compile (the qp xApp image installs gcc for the
# same reason: "sdl uses hiredis which needs gcc").
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc libc6-dev \
 && rm -rf /var/lib/apt/lists/*

# ricxappframe==3.2.2 matches the QP xApp (xApps/qp/setup.py); it provides the rmr
# python binding but expects librmr present at runtime (vendored above).
RUN pip install --no-cache-dir ricxappframe==3.2.2

WORKDIR /opt/inject
CMD ["sleep", "7200"]
