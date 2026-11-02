#!/usr/bin/env python3
"""Compile the pinned O-RAN ASN.1 inputs in asn/ into pycrate Python modules.

    compile-asn.py <asn-dir> <out-dir>

Writes <out-dir>/__init__.py plus one module per module set:
  E2AP_v0301      E2AP v03.01 (six files, sim-e2-interface)
  E2SM_KPM_v0300  generic E2SM v03.01 common IEs + E2SM-KPM v03.00 (sim-e2-interface)
  E2SM_RC_v0200   rc@a2282ee e2sm-common.asn + e2sm-rc-2.0.asn
The two E2SM sets are compiled apart because both define a module named
E2SM-COMMON-IEs (their contents are identical once comments are dropped).

The committed .asn files stay byte-identical to upstream (see asn/SOURCES.txt).
pycrate rejects three spots in them, so the compiler sees a copy with the
minimal edits in EDITS applied. Each edit must match exactly once, so a changed
input fails the build instead of compiling silently. None changes an encoding.
"""
import os
import shutil
import subprocess
import sys
import tempfile

SETS = {
    "E2AP_v0301": ["e2ap-common-v03.01.asn", "e2ap-constant-v03.01.asn", "e2ap-container-v03.01.asn",
                   "e2ap-ied-v03.01.asn", "e2ap-pdu-v03.01.asn", "e2ap-epd-v03.01.asn"],
    "E2SM_KPM_v0300": ["e2sm-v03.01.asn", "e2sm-kpm-v03.00.asn"],
    "E2SM_RC_v0200": ["e2sm-common.asn", "e2sm-rc-2.0.asn"],
}

# (file, exact old text, new text, reason). Documented in asn/SOURCES.txt.
EDITS = [
    ("e2ap-pdu-v03.01.asn", "\tRICsubscriptionTime,\n", "\tRICsubscriptionTime,\n\tRICtimeToWait,\n",
     "E2AP-PDU-Contents uses RICtimeToWait (defined in E2AP-IEs) without importing it"),
    ("e2ap-epd-v03.01.asn", "\tRICqueryRequest,\n\tRICqueryResponse,\n\tRICqueryFailure\n",
     "\tRICQueryRequest,\n\tRICQueryResponse,\n\tRICQueryFailure\n",
     "E2AP-PDU-Descriptions imports RICquery* but E2AP-PDU-Contents defines and the EP set uses RICQuery*"),
    ("e2sm-rc-2.0.asn", "RANParameter-ID \t::= INTEGER (1..2^32, ...)",
     "RANParameter-ID \t::= INTEGER (1..4294967295, ...)",
     "'2^32' is not ASN.1 value notation; the bound is the one O-RAN E2SM-RC v03.00 states in its ASN.1 "
     "(RANParameter-ID ::= INTEGER (1..4294967295, ...), Zotero JRDTL7XS p. 287)"),
]


def apply_edits(work):
    for name, old, new, _reason in EDITS:
        path = os.path.join(work, name)
        with open(path, encoding="utf-8") as f:
            text = f.read()
        if text.count(old) != 1:
            sys.exit(f"compile-asn: edit for {name} matches {text.count(old)} times (expected 1)")
        with open(path, "w", encoding="utf-8") as f:
            f.write(text.replace(old, new))


def find_compiler():
    exe = shutil.which("pycrate_asn1compile.py")
    if not exe:
        sys.exit("compile-asn: pycrate_asn1compile.py not on PATH")
    return exe


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    asn_dir, out_dir = sys.argv[1], sys.argv[2]
    compiler = find_compiler()
    os.makedirs(out_dir, exist_ok=True)
    with tempfile.TemporaryDirectory() as work:
        for files in SETS.values():
            for name in files:
                shutil.copy(os.path.join(asn_dir, name), work)
        apply_edits(work)
        for mod, files in SETS.items():
            out = os.path.join(out_dir, mod)
            cmd = [sys.executable, compiler, "-i", *[os.path.join(work, f) for f in files], "-o", out]
            res = subprocess.run(cmd, capture_output=True, text=True)
            # pycrate's compiler prints errors but may still exit 0 with an empty module.
            if res.returncode != 0 or os.path.getsize(out + ".py") == 0:
                sys.stderr.write(res.stdout + res.stderr)
                sys.exit(f"compile-asn: {mod} failed")
            print(f"compile-asn: {mod}.py {os.path.getsize(out + '.py')} bytes")
    with open(os.path.join(out_dir, "__init__.py"), "w", encoding="utf-8") as f:
        f.write('"""pycrate modules compiled at image build time by compile-asn.py."""\n')


if __name__ == "__main__":
    main()
