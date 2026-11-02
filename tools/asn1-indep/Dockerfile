# asn1-indep: an E2AP / E2SM-RC / E2SM-KPM / X2AP / NR RRC codec on pycrate,
# independent of asn1c. The O-RAN ASN.1 in asn/ (pinned in asn/SOURCES.txt) is
# compiled here, at build time, so the image runs offline (--network=none).
# X2AP (TS 36.423) and RRCNR (TS 38.331) are pycrate's bundled modules.
FROM docker.io/library/python:3.12-slim@sha256:b18b261e1b4974b4f321451ad5251ded85abb22c2b8b262da527dda1d031ab30

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 PYTHONUNBUFFERED=1 PYTHONPATH=/opt/asn1-indep
COPY requirements.txt /tmp/requirements.txt
# pycrate_asn1dir ships ~90 precompiled specs (~230 MB with bytecode); only X2AP
# and RRCNR are used, so the others are deleted in the same layer.
RUN pip install --no-cache-dir --no-deps --require-hashes --root-user-action=ignore -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt \
    && cd "$(python3 -c 'import os, pycrate_asn1dir; print(os.path.dirname(pycrate_asn1dir.__file__))')" \
    && find . -maxdepth 1 -name '*.py' ! -name __init__.py ! -name X2AP.py ! -name RRCNR.py -delete \
    && find __pycache__ -name '*.pyc' ! -name '__init__.*' ! -name 'X2AP.*' ! -name 'RRCNR.*' -delete \
    && python3 -c 'from pycrate_asn1dir import X2AP, RRCNR'

WORKDIR /opt/asn1-indep
COPY asn/ asn/
COPY compile-asn.py ./
RUN python3 compile-asn.py asn e2indep_gen && python3 -m compileall -q e2indep_gen
COPY e2indep/ e2indep/
COPY selftest.py selftest_kpm_and_fixtures.py ./
RUN python3 -m compileall -q e2indep

CMD ["python3", "/opt/asn1-indep/selftest.py"]
