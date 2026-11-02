"""e2indep: an E2AP / E2SM-RC / E2SM-KPM / X2AP / NR RRC codec built on pycrate,
independent of the asn1c-generated codecs used by the agents and the xApps.

Modules: e2ap (E2AP v03.01 PDUs), e2sm_rc (E2SM-RC v2.0 control and RAN
function definition), kpm (E2SM-KPM v03.00 indication decode), x2ap (X2AP
EN-DC X2 Setup and the NR RRC MeasurementTimingConfiguration), codec (shared
PER helpers). The O-RAN modules are compiled at image build time into the
e2indep_gen package (see compile-asn.py); X2AP and RRCNR are pycrate's bundled
pycrate_asn1dir modules. Provenance: asn/SOURCES.txt.
"""
