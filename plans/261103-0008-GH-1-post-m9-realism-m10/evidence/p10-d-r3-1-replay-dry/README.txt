P10 D-R3-1 hand-off (P09 exit review kongming-261106-0414 §7, "D-R3-1's new X2 bytes"; ledger rows 143-144): dry run of
the TS xApp key parser (scripts/gates/replay-ts-cell-map.py) on synthetic e2mgr records for en-gNB IDs 2..12 and the eNB
at the corrected served NR cell: NRARFCN 632758 (Point A), nR-TxBW scs60/nrb24, MTC SSB at NR-ARFCN 633312, PCI = gNB ID,
the agent's cell (ns3_e2_agent e2-node-identity.hpp). Records: gen-nodeb.py (adapted from ../p09-replay-dry/gen-nodeb.py,
which used NRARFCN and MTC 633333 with the encoder's default scs30/nrb106), run in localhost/asn1-indep:09aeabb8b0f99b0c.
nodeb-02.json's request part equals the agent's regenerated kReqEnGnb2 (codec-probe-e2ap.cpp). Command:
  replay-ts-cell-map.py nodeb-*.json --expect %08X10=en_gnb_001_001_%08x (n = 2..12) \
      --no-key enB_macro_001_001_000001 --no-wrong-node
Result (replay-out.json): exit 0, and replay-out.json is byte-identical to ../p09-replay-dry/replay-out.json: every
en-gNB owns exactly its 0x..00 and 0x..10 keys, no key has two owners, the eNB owns no key. The new X2 bytes add no
spurious key. nodeb-enb.json is byte-identical to p09's (the eNB's request part carries no NR frequency).
