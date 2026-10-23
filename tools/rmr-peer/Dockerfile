# RMR peers for gate r2 (stub QP xApp and the host-side RMR injector), built from a minimal pinned base.
# Never built from QP's Dockerfile: that one carries the Influx token edit made at install time.
FROM python:3.11-slim-bookworm@sha256:f06d01d4ba3f8ad5af45a3ec87df19c1d317d8e8961edc0fabda61811af6f7cf

# RMR 4.9.0 (the version QP's own image uses), checked by sha256.
ARG RMR_URL=https://packagecloud.io/o-ran-sc/release/packages/debian/stretch/rmr_4.9.0_amd64.deb/download.deb
ARG RMR_SHA256=1b7e5586a81c4be8829b450f4701d4b2309047ba73de5ac51b1c6861f029c14f
RUN python3 -c "import sys, urllib.request; urllib.request.urlretrieve(sys.argv[1], '/tmp/rmr.deb')" "$RMR_URL" && \
    echo "$RMR_SHA256  /tmp/rmr.deb" | sha256sum -c - && dpkg -i /tmp/rmr.deb && rm /tmp/rmr.deb

# Only the ctypes RMR wrapper of ricxappframe is used; it imports nothing outside the package.
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --no-deps --require-hashes -r /tmp/requirements.txt && rm /tmp/requirements.txt

ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64 PYTHONUNBUFFERED=1
COPY stub-qp-rmr-peer.py rmr-injector.py rmr-peer-selftest.py /app/
CMD ["python3", "-I", "/app/stub-qp-rmr-peer.py"]
