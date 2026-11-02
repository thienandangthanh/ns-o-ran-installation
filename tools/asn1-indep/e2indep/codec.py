"""PER encode/decode over the pycrate runtime, plus value helpers shared by the
protocol modules.

pycrate values: SEQUENCE -> dict, CHOICE -> (alternative, value), BIT STRING ->
(int, bit length), OCTET STRING -> bytes, ENUMERATED -> name, open type ->
(type name, value). pycrate checks sizes and ranges on encode but not that a
BIT STRING's integer fits its bit length, hence bitstr().
"""
from pycrate_core.charpy import Charpy


class CodecError(ValueError):
    """An encode or decode failed; the message names the ASN.1 type."""


def _name(obj):
    return getattr(obj, "_name", type(obj).__name__)


def encode(obj, val, aligned=True):
    """Encode val as obj (a pycrate ASN.1 type object) in APER (or UPER)."""
    try:
        return obj.to_aper(val) if aligned else obj.to_uper(val)
    except Exception as exc:  # pycrate raises several unrelated exception types
        raise CodecError(f"encode {_name(obj)}: {exc}") from exc


def decode(obj, buf, aligned=True):
    """Decode buf as obj; every octet must be consumed. Returns the value."""
    if not isinstance(buf, (bytes, bytearray)) or not buf:
        raise CodecError(f"decode {_name(obj)}: need non-empty bytes")
    char = Charpy(bytes(buf))
    try:
        obj.from_aper(char) if aligned else obj.from_uper(char)
    except Exception as exc:
        raise CodecError(f"decode {_name(obj)}: {exc}") from exc
    rest = char.len_bit()
    if rest:
        raise CodecError(f"decode {_name(obj)}: {rest // 8} trailing octets of {len(buf)}")
    return obj.get_val()


def bitstr(value, nbits):
    """BIT STRING value of exactly nbits bits holding the unsigned integer value."""
    if not isinstance(value, int) or not isinstance(nbits, int) or nbits <= 0:
        raise CodecError(f"bitstr: bad value/length {value!r}/{nbits!r}")
    if not 0 <= value < (1 << nbits):
        raise CodecError(f"bitstr: {value:#x} does not fit in {nbits} bits")
    return (value, nbits)


def plmn(value):
    """Validate a PLMN identity: 3 TBCD octets (e.g. bytes.fromhex('00F110') = MCC 001 MNC 01).

    Every nibble must be a digit, except the MNC filler nibble 0xF (high nibble of
    the second octet, used for 2-digit MNCs)."""
    if not isinstance(value, (bytes, bytearray)) or len(value) != 3:
        raise CodecError(f"plmn: need 3 octets, got {value!r}")
    nibbles = [n for b in value for n in (b & 0x0F, b >> 4)]
    for i, n in enumerate(nibbles):
        if n > 9 and not (i == 3 and n == 0xF):
            raise CodecError(f"plmn: {bytes(value).hex()} is not TBCD")
    return bytes(value)


def plmn_digits(value):
    """'00F110' -> ('001', '01'): MCC and MNC digit strings of a PLMN identity."""
    b = plmn(value)
    mcc = f"{b[0] & 0xF}{b[0] >> 4}{b[1] & 0xF}"
    mnc = f"{b[2] & 0xF}{b[2] >> 4}" + ("" if b[1] >> 4 == 0xF else f"{b[1] >> 4}")
    return mcc, mnc
