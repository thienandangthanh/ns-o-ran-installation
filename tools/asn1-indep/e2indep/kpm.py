"""E2SM-KPM v03.00 indication decode (APER), enough for wire checks: the
collection start time of the header, and the measurement records, measurement
names and UE IDs of the message (Formats 1, 2 and 3).

Records: one list per MeasurementDataItem, each item a MeasurementRecordItem
CHOICE tuple, e.g. [('integer', 7), ('real', 1.5), ('noValue', 0)].
"""
from e2indep_gen import E2SM_KPM_v0300 as _M

from .codec import decode

_I = _M.E2SM_KPM_IEs
HEADER, MESSAGE = _I.E2SM_KPM_IndicationHeader, _I.E2SM_KPM_IndicationMessage


def decode_indication_header(buf):
    """{'format', 'collect_start_time' (8 octets), 'sender_name', 'sender_type', 'vendor_name',
    'file_format_version', 'raw'}."""
    fmt, val = decode(HEADER, buf)["indicationHeader-formats"]
    return {"format": fmt, "collect_start_time": val.get("colletStartTime"), "sender_name": val.get("senderName"),
            "sender_type": val.get("senderType"), "vendor_name": val.get("vendorName"),
            "file_format_version": val.get("fileFormatversion"), "raw": val}


def _meas_name(item):
    alt, v = item["measType"]
    return v if alt == "measName" else f"id:{v}"


def _format1(f1):
    return {"records": [d["measRecord"] for d in f1["measData"]],
            "meas_names": [_meas_name(i) for i in f1.get("measInfoList", [])],
            "granularity_period": f1.get("granulPeriod")}


def decode_indication_message(buf):
    """{'format', 'records', 'meas_names', 'granularity_period', 'ue_reports', 'raw'}.

    Format 1: records/meas_names of the message, ue_reports [].
    Format 2: records, meas_names from measCondUEidList, ue_reports [{'ue_id', ...}]
              for every matched UE ID (records not split per UE).
    Format 3: one entry per UEMeasurementReportItem: {'ue_id', 'records', 'meas_names', ...};
              the top-level records/meas_names are empty."""
    fmt, val = decode(MESSAGE, buf)["indicationMessage-formats"]
    out = {"format": fmt, "records": [], "meas_names": [], "granularity_period": None, "ue_reports": [], "raw": val}
    if fmt == "indicationMessage-Format1":
        out.update(_format1(val))
    elif fmt == "indicationMessage-Format2":
        out["records"] = [d["measRecord"] for d in val["measData"]]
        out["granularity_period"] = val.get("granulPeriod")
        for cond in val["measCondUEidList"]:
            out["meas_names"].append(_meas_name(cond))
            for match in cond.get("matchingUEidList", []):
                out["ue_reports"].append({"ue_id": match["ueID"], "meas_name": _meas_name(cond)})
    elif fmt == "indicationMessage-Format3":
        for rep in val["ueMeasReportList"]:
            out["ue_reports"].append({"ue_id": rep["ueID"], **_format1(rep["measReport"])})
    return out
