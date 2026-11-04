ue-metrics.lp: 24 UeMetrics points (line protocol, no timestamps; ts-influx-query-selftest.py stamps them a few
seconds before now) of the ueId tags enGnbUeId:1@00F110-00001 and enGnbUeId:2@00F110-00001, three points each of
two integer fields (CARR.PDSCHMCSDist.Bin1, Bin2) and two float fields (DRB.UEThpDl, DRB.BufferSize.Qos). Cut from
the kpimon bucket dump of evidence/r2/20261104T190033Z live1 (influx-kpimon.csv), each point keeping its table's
type, so the bucket holds both field types, as a live kpimon bucket does.
