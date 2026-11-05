P09 hand-off (P06 exit review kongming-261104-1340; P08 exit review item 3): dry run of the TS xApp key parser
(scripts/gates/replay-ts-cell-map.py at harness 8aaee98) on synthetic e2mgr records for en-gNB IDs 2..12 and the eNB.
Records: gen-nodeb.py, run in localhost/asn1-indep:09aeabb8b0f99b0c (the independent encoder; the request part is the
uppercase hex text of the APER EN-DC X2 SETUP REQUEST, as e2mgr stores it). Command:
  replay-ts-cell-map.py nodeb-*.json --expect %08X10=en_gnb_001_001_%08x (n = 2..12) \
      --no-key enB_macro_001_001_000001 --no-wrong-node
Result (replay-out.json): exit 0. Every en-gNB owns exactly its 0x..00 and 0x..10 keys, no key has two owners, IDs 10..12
give upper-cased hex-letter keys (0000000A10, 0000000B10, 0000000C10), and the eNB owns no key. The live s10 run
checks the same on e2mgr's real records.
