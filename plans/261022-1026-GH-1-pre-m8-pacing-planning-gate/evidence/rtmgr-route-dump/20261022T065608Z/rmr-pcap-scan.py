# Scan TCP payloads for RMR v3 headers (mtype, plen, ver=3 as network-order int32; sub_id at +212 (timespec 8-byte aligned at +176), meid at +140).
import sys, struct, collections
want = {12010,12011,12040,12041,12042,12050,12020,12021}
cnt = collections.Counter(); rows = []
for line in open(sys.argv[1]):
    f = line.rstrip("\n").split("\t")
    if len(f) < 4 or not f[3]: continue
    b = bytes.fromhex(f[3].replace(":", ""))
    for i in range(0, len(b) - 216):
        mt, pl, ver = struct.unpack_from(">iii", b, i)
        if ver == 3 and mt in want and 0 <= pl < 65536:
            sid = struct.unpack_from(">i", b, i + 212)[0]
            meid = b[i+140:i+172].split(b"\0")[0].decode("latin1")
            src = b[i+76:i+140].split(b"\0")[0].decode("latin1")
            cnt[(mt, f[0], f[1], f[2], sid)] += 1
            rows.append((mt, sid, f[0], f[1], f[2], meid, src))
for k, v in sorted(cnt.items()): print("mtype=%d src=%s dst=%s:%s sub_id=%d count=%d" % (*k, v))
print("by mtype:", dict(collections.Counter(r[0] for r in rows)))
for r in rows:
    if r[0] in (12040, 12041, 12042): print("  ", r)
