#!/usr/bin/env python3
"""ns3-source-lint.py: the EN-DC (MC) PDCP paths of the ns-3 tree never name the E-UTRA PDCP header class.

Over every *.h and *.cc under src/, scratch/ and contrib/ (src/*/bindings/ excluded: dead pybindgen, the build runs
with --disable-python), each read as translation phases 1-2 read it (CRLF and lone CR become LF, then every
line splice, a backslash then optional horizontal whitespace then a newline, is deleted), with C/C++ comments and string and character literals blanked; problems name the
original physical lines:
  1. \\bLtePdcpHeader\\b matches only in the ALLOWED files, and in a file with a count there on exactly that many code
     lines. An allowlist, so that a new MC consumer in a new file is caught.
  2. Each file of MUST_BE_ZERO (the MC paths and every header consumer) exists. Its count of 0 already follows from
     rule 1, so the list documents the consumers and catches a rename that would leave it stale.
  3. The POSITIVE code facts hold.

  ns3-source-lint.py --git REPO SHA   the tree committed at SHA in the git repo REPO (its working tree is not read)
  ns3-source-lint.py --dir DIR        the files under DIR (fixtures; a look at uncommitted work, never a gate)
  ns3-source-lint.py --self-test
Exit 0 pass, 1 a rule fails, 2 the tree cannot be read.
"""
import bisect
import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOTS = ("src/", "scratch/", "contrib/")
FORBIDDEN_NAME = "LtePdcpHeader"
FORBIDDEN = re.compile(r"\b%s\b" % FORBIDDEN_NAME)
# a line splice (after normalize), deleted in translation phase 2. GCC, which builds ns-3, also takes a backslash
# followed by horizontal whitespace before the newline as a splice (warning "backslash and newline separated by
# space"), so trailing blanks after a backslash never hide code from this rule
SPLICE = re.compile(r"\\[ \t\f\v]*\n")
# path -> None (any count) or the exact number of code lines that may match
ALLOWED = {
    "src/lte/model/lte-pdcp-header.h": None,         # the class
    "src/lte/model/lte-pdcp-header.cc": None,
    # the E-UTRA entity's own codec, behind AssertEUtraEntity(): CreateDataPduHeader, the header variable and DATA_PDU
    # in DoTransmitPdcpSdu, the header variable in DoReceivePdu
    "src/lte/model/lte-pdcp.cc": 4,
    "src/lte/test/lte-test-entities.cc": None,       # the RLC-test entity, an E-UTRA context
    "src/lte/test/lte-test-mc-pdcp-nr-header.cc": None,  # its SRB checks
}
MUST_BE_ZERO = (
    "src/lte/model/mc-enb-pdcp.h", "src/lte/model/mc-enb-pdcp.cc",
    "src/lte/model/mc-ue-pdcp.h", "src/lte/model/mc-ue-pdcp.cc",
    "src/lte/model/lte-enb-rrc.h", "src/lte/model/lte-enb-rrc.cc",
    "src/lte/model/lte-ue-rrc.h", "src/lte/model/lte-ue-rrc.cc",
    "src/lte/model/lte-rlc-am.h", "src/lte/model/lte-rlc-am.cc",
    "src/lte/model/lte-pdcp-sn-wrap.h", "src/lte/model/lte-pdcp-sn-wrap.cc",
    "src/mmwave/model/mmwave-enb-net-device.cc",
    "scratch/scenario-zero.cc",
    "src/lte/test/lte-test-pdcp-sn-wrap.cc",
)
USING_NR = re.compile(r"\busing\s+DataPduHeader\s*=\s*NrPdcpHeader\s*;")
# an explicit instantiation: `template` not followed by a parameter list, up to its `;`
EXPLICIT_INST = re.compile(r"\btemplate\s+(?!<)[^;{}]*;")
NR_INST = re.compile(r"\bRlcPdusToRlcSdus\s*<\s*NrPdcpHeader\s*>")
NR_HDR_SIZE = re.compile(r"\bMcEnbPdcp::DataPduHeader\s*\(\s*\)\s*\.\s*GetSerializedSize\s*\(\s*\)")


def positive_problems(code):
    """Problems of the positive facts, on comment- and literal-free code (path -> text)."""
    bad = []
    for p in ("src/lte/model/mc-enb-pdcp.h", "src/lte/model/mc-ue-pdcp.h"):
        if not USING_NR.search(code.get(p, "")):
            bad.append("%s: no `using DataPduHeader = NrPdcpHeader;`" % p)
    am = "src/lte/model/lte-rlc-am.cc"
    inst = [m.group(0) for m in EXPLICIT_INST.finditer(code.get(am, ""))]
    if len(inst) != 1 or not NR_INST.search(inst[0]):
        bad.append("%s: explicit instantiations %s, want exactly one, for RlcPdusToRlcSdus<NrPdcpHeader>" % (
            am, [" ".join(i.split()) for i in inst]))
    nd = "src/mmwave/model/mmwave-enb-net-device.cc"
    if not NR_HDR_SIZE.search(code.get(nd, "")):
        bad.append("%s: no McEnbPdcp::DataPduHeader().GetSerializedSize()" % nd)
    return bad


def normalize(text):
    """CRLF and lone CR to LF, as the compiler maps physical line ends (phase 1); idempotent."""
    return text.replace("\r\n", "\n").replace("\r", "\n")


def decode(data):
    """A source file's bytes as text for the lint: undecodable bytes replaced (they hold no identifier), then
    normalize. Both readers use it, so a --git and a --dir read of the same bytes give the same text."""
    return normalize(data.decode("utf-8", errors="replace"))


class Spliced:
    """A file after translation phase 2, with offset maps to and from its normalized original text.

    Phase 2 deletes every SPLICE match (of any length) in one pass over the original (one that only appears after a deletion is
    kept, as the compiler keeps it). Raw string literals revert it: the lexer recognises a raw opener on the spliced
    text (an opener may itself be formed across splices) and finds its `)delim"` terminator in the original text,
    where the body's splices are still in place (see strip_code)."""

    def __init__(self, orig):
        self.orig = orig
        kept, self.seg_spliced, self.seg_orig, pos, at = [], [], [], 0, 0
        for m in SPLICE.finditer(orig):
            self.seg_spliced.append(at)
            self.seg_orig.append(pos)
            kept.append(orig[pos:m.start()])
            at += m.start() - pos
            pos = m.end()
        self.seg_spliced.append(at)
        self.seg_orig.append(pos)
        kept.append(orig[pos:])
        self.text = "".join(kept)
        self.newlines = [i for i, c in enumerate(orig) if c == "\n"]

    def to_orig(self, off):
        """the original offset of spliced offset off"""
        k = bisect.bisect_right(self.seg_spliced, off) - 1
        return self.seg_orig[k] + off - self.seg_spliced[k]

    def to_spliced(self, o):
        """the first spliced offset whose original offset is >= o"""
        k = bisect.bisect_right(self.seg_orig, o) - 1
        length = (self.seg_spliced[k + 1] if k + 1 < len(self.seg_spliced) else len(self.text)) - self.seg_spliced[k]
        return self.seg_spliced[k] + min(o - self.seg_orig[k], length)

    def line_of(self, off):
        """the original physical line of spliced offset off"""
        return bisect.bisect_left(self.newlines, self.to_orig(off)) + 1


IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
# a C++14 pp-number: a digit (or . digit), then digits, identifier characters, ' followed by a digit or a nondigit (the
# digit separator, so 1'000 and 0x1'FF are one token), exponent signs e+ e- p+ p-, and dots
PP_NUMBER = re.compile(r"\.?[0-9](?:[eEpP][+-]|'[A-Za-z0-9_]|[A-Za-z0-9_.])*")
LITERAL_PREFIXES = {"L", "u", "U", "u8"}   # encoding prefixes of character and string literals
RAW_PREFIXES = {"R", "LR", "uR", "UR", "u8R"}


def strip_code(src):
    """text with comments and string/character literals (with any encoding prefix, raw strings included) blanked to
    spaces, newlines kept (so line numbers hold). Identifiers and pp-numbers are read whole, so an apostrophe inside a
    number is a digit separator and one after an identifier that is not a prefix starts a character literal. A
    pp-number takes its ud-suffix with it (12_km, 1uR are one token); a closed string or character literal takes the
    identifier right after its closing quote as its ud-suffix, so "x"R"(...)" is one literal, then a second one.
    Lexes src.text, the spliced text, so a line splice can no longer extend or end a comment or ordinary literal
    unseen; a raw string's body keeps its splices (its terminator is found in the original text). Returns a string of
    src.text's length, so its offsets map back through src."""
    text = src.text
    out, i, n = [], 0, len(text)

    def blank(s):
        return "".join(c if c == "\n" else " " for c in s)

    def quoted(j):
        """end of the ordinary literal whose opening quote is at j (escape-aware; stops at an unescaped newline)"""
        q, j = text[j], j + 1
        while j < n and text[j] != q and text[j] != "\n":
            j += 2 if text[j] == "\\" else 1
        return min(j + 1, n)
    while i < n:
        c, nx = text[i], text[i + 1] if i + 1 < n else ""
        if c == "/" and nx == "/":
            j = text.find("\n", i)
            j = n if j < 0 else j
        elif c == "/" and nx == "*":
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
        elif c.isalpha() or c == "_":
            word = IDENT.match(text, i).group(0)
            after = i + len(word)
            q = text[after] if after < n else ""
            m = re.compile(r'"([^ ()\\\t\n]{0,16})\(').match(text, after) if word in RAW_PREFIXES else None
            if m:
                # the body starts right after the opener's "(" in the original text and ends at the first literal
                # `)delim"` there: splices inside the body are reverted, so the terminator is never formed by one
                body = src.to_orig(m.end() - 1) + 1
                close = src.orig.find(")" + m.group(1) + '"', body)
                j = n if close < 0 else src.to_spliced(close + len(m.group(1)) + 2)
            elif word in LITERAL_PREFIXES and q in ("'", '"'):
                j = quoted(after)
            else:
                out.append(word)
                i = after
                continue
        elif c.isdigit() or (c == "." and nx.isdigit()):
            j = PP_NUMBER.match(text, i).end()
            out.append(text[i:j])
            i = j
            continue
        elif c in ("'", '"'):
            j = quoted(i)
        else:
            out.append(c)
            i += 1
            continue
        if text[i] != "/" and text[j - 1] in ("'", '"'):
            # every branch reaching here blanks a comment (starting with /) or a literal; a literal closed by its
            # quote (an unclosed one ends at a newline or at the end of the file) runs on through its ud-suffix, so
            # lexing resumes after it, never at a prefix-like suffix such as R or u8
            m = IDENT.match(text, j)
            j = m.end() if m else j
        out.append(blank(text[i:j]))
        i = j
    return "".join(out)


def in_scope(path):
    return path.startswith(ROOTS) and path.endswith((".h", ".cc")) and not re.match(r"src/[^/]+/bindings/", path)


def read_git(repo, sha):
    names = subprocess.run(["git", "-C", repo, "ls-tree", "-r", "--name-only", sha, "--", "src", "scratch", "contrib"],
                           check=True, capture_output=True).stdout.decode().splitlines()
    paths = [p for p in names if in_scope(p)]
    if not paths:
        raise RuntimeError("no *.h/*.cc under src, scratch, contrib at %s" % sha)
    batch = subprocess.run(["git", "-C", repo, "cat-file", "--batch"], check=True, capture_output=True,
                           input="".join("%s:%s\n" % (sha, p) for p in paths).encode()).stdout
    files, pos = {}, 0
    for p in paths:
        eol = batch.index(b"\n", pos)
        head = batch[pos:eol].split()
        if len(head) != 3 or head[1] != b"blob":
            raise RuntimeError("%s:%s is not a blob: %s" % (sha, p, batch[pos:eol].decode(errors="replace")))
        size = int(head[2])
        files[p] = decode(batch[eol + 1:eol + 1 + size])
        pos = eol + 1 + size + 1
    return files


def read_dir(root):
    root = pathlib.Path(root)
    return {p.relative_to(root).as_posix(): decode(p.read_bytes())
            for p in root.rglob("*") if p.is_file() and in_scope(p.relative_to(root).as_posix())}


def lint(files):
    """The problems of a tree (path -> source text, normalized again here so in-memory fixtures read as the readers
    do); files out of scope are not read. A count is of distinct original physical lines holding a match start."""
    code, hits, bad = {}, {}, []
    for p, t in files.items():
        if in_scope(p):
            src = Spliced(normalize(t))
            code[p] = strip_code(src)
            hits[p] = sorted({src.line_of(m.start()) for m in FORBIDDEN.finditer(code[p])})
    for p in sorted(code):
        lines = hits[p]
        if not lines or (p in ALLOWED and ALLOWED[p] in (None, len(lines))):
            continue
        if p in ALLOWED:
            bad.append("%s: LtePdcpHeader on %d code lines %s, want exactly %d" % (p, len(lines), lines, ALLOWED[p]))
        else:
            bad.append("%s: LtePdcpHeader on code lines %s (not an allowed file)" % (p, lines))
    bad += ["%s: missing (a listed MC PDCP consumer)" % p for p in MUST_BE_ZERO if p not in code]
    return bad + positive_problems(code)


def self_test():
    good = {
        "src/lte/model/lte-pdcp-header.h": "class LtePdcpHeader : public Header {};\n",
        "src/lte/model/lte-pdcp-header.cc": "LtePdcpHeader::LtePdcpHeader() {}\n",
        "src/lte/model/lte-pdcp.cc": ("// LtePdcpHeader is the E-UTRA codec\nreturn std::make_unique<LtePdcpHeader>();\n"
                                      "LtePdcpHeader pdcpHeader;\nh.SetDcBit(LtePdcpHeader::DATA_PDU);\n"
                                      "LtePdcpHeader pdcpHeader;\n"),
        "src/lte/test/lte-test-entities.cc": "LtePdcpHeader h;\n",
        "src/lte/helper/lte-helper.cc": 'LogComponentEnable("LtePdcpHeader", logLevel);\n',
        "src/lte/bindings/modulegen.cc": "LtePdcpHeader x;\n",
        "src/lte/model/mc-enb-pdcp.h": "class McEnbPdcp {\n  public:\n    using DataPduHeader = NrPdcpHeader;\n};\n",
        "src/lte/model/mc-ue-pdcp.h": "class McUePdcp {\n    using DataPduHeader = NrPdcpHeader;\n};\n",
        "src/lte/model/lte-rlc-am.cc": ("template <class PdcpHeader>\nvoid LteRlcAm::RlcPdusToRlcSdus(int x) {}\n"
                                        "template void LteRlcAm::RlcPdusToRlcSdus<NrPdcpHeader>(int x);\n"),
        "src/mmwave/model/mmwave-enb-net-device.cc": "auto h = McEnbPdcp::DataPduHeader().GetSerializedSize();\n",
    }
    for p in MUST_BE_ZERO:
        good.setdefault(p, "// %s\n" % p)

    def put(path, text):
        return lambda t: t.__setitem__(path, text)

    def add(path, text):
        return lambda t: t.__setitem__(path, t[path] + text)

    def drop(path):
        return lambda t: t.pop(path)
    new = "src/lte/model/new-mc-consumer.cc"
    cases = [  # (name, mutation, wanted pass)
        ("the good tree", lambda t: None, True),
        ("a forbidden hit in a new file", put(new, "void F() { LtePdcpHeader h; }\n"), False),
        ("a hit in a line comment of a new file", put(new, "// not LtePdcpHeader\nint x;\n"), True),
        ("a hit in a block comment over lines", put(new, "/* the E-UTRA\n   LtePdcpHeader */ int x;\n"), True),
        ("a hit in a string literal", put(new, 'auto s = "LtePdcpHeader\\" (quoted)";\n'), True),
        ("a hit in a raw string literal", put(new, 'auto s = R"x(LtePdcpHeader)" )x";\n'), True),
        ("a hit after a quote character literal", put(new, "char q = '\"'; LtePdcpHeader h;\n"), False),
        ("a hit after a digit separator", put(new, "int n = 1'000; LtePdcpHeader h;\n"), False),
        ("a hit after a hex digit separator", put(new, "int n = 0x1'FF; LtePdcpHeader h;\n"), False),
        ("a hit after a binary digit separator", put(new, "int n = 0b1'01; LtePdcpHeader h;\n"), False),
        ("a hit after an exponent and separator", put(new, "double x = 1'0e+3; LtePdcpHeader h;\n"), False),
        ("a hit after L'\"'", put(new, "wchar_t q = L'\"'; LtePdcpHeader h;\n"), False),
        ("a hit after u'\"'", put(new, "char16_t q = u'\"'; LtePdcpHeader h;\n"), False),
        ("a hit after U'\"'", put(new, "char32_t q = U'\"'; LtePdcpHeader h;\n"), False),
        ("a hit after u8'\"'", put(new, "char8_t q = u8'\"'; LtePdcpHeader h;\n"), False),
        ("a hit after u8\"\\\"\"", put(new, 'auto s = u8"\\""; LtePdcpHeader h;\n'), False),
        ("a hit after a char literal right behind an identifier", put(new, "return'\"'; } LtePdcpHeader h;\n"), False),
        ("a hit in an L string", put(new, 'auto s = L"LtePdcpHeader";\n'), True),
        ("a hit in a u8 string", put(new, 'auto s = u8"LtePdcpHeader";\n'), True),
        ("a hit in a u8R raw string", put(new, 'auto s = u8R"d(LtePdcpHeader")d";\n'), True),
        ("a hit in an LR raw string over lines", put(new, 'auto s = LR"(\nLtePdcpHeader\n)";\nint y;\n'), True),
        ("a hit after a raw string", put(new, 'auto s = uR"(x)"; LtePdcpHeader h;\n'), False),
        ("a splice in a string hides code", put(new, 'auto s = "\\\\\\\nn"; LtePdcpHeader h;\n'), False),
        ("a splice in an L string hides code", put(new, 'auto s = L"\\\\\\\nn"; LtePdcpHeader h;\n'), False),
        ("a splice in a u8 string hides code", put(new, 'auto s = u8"\\\\\\\nn"; LtePdcpHeader h;\n'), False),
        ("a splice behind an escaped backslash", put(new, 'auto s = "a\\\\\nb"; LtePdcpHeader h;\n'), False),
        ("a CRLF splice behind an escaped backslash hides nothing", put(new, 'auto s = "a\\\\\r\nb";\r\nint y; // LtePdcpHeader\r\n'),
         True),
        ("an escaped backslash ending a line is no splice", put(new, 'auto s = "a\\\\";\nint y;\n'), True),
        ("a CRLF splice in a string hides nothing", put(new, '// LtePdcpHeader\r\nauto s = "a\\\r\nb";\r\nint y;\r\n'), True),
        ("a splice in a literal of a file without the name", put(new, 'auto s = "a\\\nb";\nint y;\n'), True),
        ("a CRLF splice in a char literal of a file without the name", put(new, "char c = '\\\r\nn'; int y;\r\n"), True),
        ("a splice, the name only in a comment elsewhere", put(new, '/* LtePdcpHeader */\nauto s = "a\\\nb";\nint y;\n'),
         True),
        ("a splice in a char literal hides nothing", put(new, "char c = '\\\\\nn'; int y; // LtePdcpHeader\n"), True),
        ("the name spelled across a code splice", put(new, "LtePdcp\\\nHeader h;\n"), False),
        ("the name spelled across a splice inside a literal is a string", put(new, 'auto s = "LtePdcp\\\nHeader";\n'),
         True),
        ("a splice in a raw string is no splice", put(new, 'auto s = R"(a\\\nb)";\nint y;\n'), True),
        ("code after a raw string ending behind a backslash-newline", put(new, 'auto s = R"(a\\\n)"; LtePdcpHeader h;\n'),
         False),
        ("a macro continuation without the name", put(new, "#define F(x) \\\n    do { g(x); } \\\n    while (0)\n"), True),
        ("a macro continuation naming it on line 2", put(new, "#define F(x) \\\n    LtePdcpHeader h; \\\n    g(x)\n"),
         False),
        ("an identifier ending in R is not a raw prefix", put(new, 'auto s = FOOR"(" LtePdcpHeader h; //)"\n'), False),
        ("a hit in an MC PDCP file", add("src/lte/model/mc-enb-pdcp.cc", "LtePdcpHeader h;\n"), False),
        ("a hit in scratch/", add("scratch/scenario-zero.cc", "ns3::LtePdcpHeader h;\n"), False),
        ("a hit in contrib/", put("contrib/oran-interface/model/x.cc", "LtePdcpHeader h;\n"), False),
        ("a longer name is not a hit", put(new, "MyLtePdcpHeaderX h;\n"), True),
        ("lte-pdcp.cc on 5 code lines", add("src/lte/model/lte-pdcp.cc", "LtePdcpHeader extra;\n"), False),
        ("lte-pdcp.cc on 3 code lines", put("src/lte/model/lte-pdcp.cc", "LtePdcpHeader a;\nLtePdcpHeader b;\n"
                                                                         "LtePdcpHeader c;\n"), False),
        ("lte-pdcp.cc: 4 matches on 3 code lines", put("src/lte/model/lte-pdcp.cc",
                                                       "LtePdcpHeader a; LtePdcpHeader b;\nLtePdcpHeader c;\n"
                                                       "LtePdcpHeader d;\n"), False),
        ("a listed consumer missing", drop("src/lte/model/lte-pdcp-sn-wrap.cc"), False),
        ("no DataPduHeader alias in mc-ue-pdcp.h", put("src/lte/model/mc-ue-pdcp.h", "class McUePdcp {};\n"), False),
        ("the alias only in a comment", put("src/lte/model/mc-enb-pdcp.h",
                                            "// using DataPduHeader = NrPdcpHeader;\n"), False),
        ("a second explicit instantiation", add("src/lte/model/lte-rlc-am.cc", "template class std::vector<int>;\n"),
         False),
        ("no explicit instantiation", put("src/lte/model/lte-rlc-am.cc", "template <class H>\nvoid F() {}\n"), False),
        ("the instantiation for another header", put("src/lte/model/lte-rlc-am.cc",
                                                     "template void LteRlcAm::RlcPdusToRlcSdus<MyHeader>(int);\n"),
         False),
        ("no NR header size in mmwave-enb-net-device.cc", put("src/mmwave/model/mmwave-enb-net-device.cc",
                                                             "auto h = 2;\n"), False),
    ]
    fails = 0
    for name, mutate, want in cases:
        tree = dict(good)
        mutate(tree)
        got = not lint(tree)
        fails += got != want
        print(("ok   " if got == want else "FAIL ") + name + ("" if got == want else ": " + "; ".join(lint(tree))))
    # regression cases through both paths: in memory, and committed byte for byte (CR kept) and read back by read_git;
    # (name, file text, wanted pass, wanted problem substring or None)
    regress = [
        ("a // comment continued by a splice", "// \\\n/*\nLtePdcpHeader h;\n// */\n", False, "code lines [3]"),
        ("Codex: a // comment continued by backslash-space-newline", "// \\ \n/*\nLtePdcpHeader h;\n// */\n", False,
         "code lines [3]"),
        ("a // comment continued by backslash-tab-newline", "// \\\t\n/*\nLtePdcpHeader h;\n// */\n", False,
         "code lines [3]"),
        ("a // comment continued by backslash-spaces-newline", "// \\    \n/*\nLtePdcpHeader h;\n// */\n", False,
         "code lines [3]"),
        ("an identifier split by backslash-space-newline", "int a;\nLtePdcp\\ \nHeader h;\n", False, "code lines [2]"),
        ("a literal splice with trailing space", 'auto s = "a\\ \n"; LtePdcpHeader h;\n', False, "code lines [2]"),
        ("a backslash then spaces then text is no splice", 'int a = 1; /* x \\  y */\nauto s = "\\  LtePdcpHeader";\n', True,
         None),
        ("a CR-only comment end", "// comment\rLtePdcpHeader h;\r", False, "code lines [2]"),
        ("a CR-only split identifier", "int a;\rLtePdcp\\\rHeader h;\r", False, "code lines [2]"),
        ("a CR-only literal splice", 'auto s = "\\\\\\\rn"; LtePdcpHeader h;\r', False, "code lines [2]"),
        ("a continued // comment without the name", "// note \\\nint x; // more\nint y;\n", True, None),
        ("a macro continuation naming it on line 2", "#define F(x) \\\n    LtePdcpHeader h; \\\n    g(x)\n", False,
         "code lines [2]"),
        ("lines after removed splices keep their number", "#define A \\\n B \\\n C\nint y;\nLtePdcpHeader h;\n", False,
         "code lines [5]"),
        ("CR-only lines keep their number", "x;\r\r\rLtePdcpHeader h;\r", False, "code lines [4]"),
        ("Codex: a splice kept inside raw string x", 'auto a = R"x()x\\\n" R"y(\n)x";\nLtePdcpHeader h;\nauto b = R"y()y";\n',
         False, "code lines [4]"),
        ("a raw body with a splice, then its terminator", 'auto a = R"d(a\\\n)d"; LtePdcpHeader h;\n', False,
         "code lines [2]"),
        ("a raw body with a splice, the name inside it", 'auto a = R"d(a\\\nLtePdcpHeader)d";\nint y;\n', True, None),
        ("a raw opener formed across a splice, the name after it", 'auto a = R\\\n"d(x)d";\nLtePdcpHeader h;\n', False,
         "code lines [3]"),
        ("a raw opener formed across a splice, the name in its body", 'auto a = R\\\n"d(LtePdcpHeader)d";\nint y;\n', True,
         None),
        ("Codex: R as the ud-suffix of a raw string", 'auto a = R"(x)"R"("; LtePdcpHeader h; } //)"\n', False,
         "code lines [1]"),
        ("R as the ud-suffix of an ordinary string", 'auto a = "x"R"("; LtePdcpHeader h; } //)"\n', False,
         "code lines [1]"),
        ("R as the ud-suffix of a character literal", 'auto a = \'x\'R"("; LtePdcpHeader h; } //)"\n', False,
         "code lines [1]"),
        ("R as the ud-suffix of a prefixed string", 'auto a = u8"x"R"("; LtePdcpHeader h; } //)"\n', False,
         "code lines [1]"),
        ("a pp-number keeps its ud-suffix", 'auto a = 1uR"("; LtePdcpHeader h; } //)"\n', False, "code lines [1]"),
        ("a ud-suffix then ordinary code", 'auto s = "abc"_sv; int y = 1;\n', True, None),
        ("a raw delimiter formed across a splice", 'auto a = R"a\\\nb(x)ab"; LtePdcpHeader h;\n', False, "code lines [2]"),
    ]

    def git_lint(tree):
        with tempfile.TemporaryDirectory() as d:
            for path, text in tree.items():
                os.makedirs(os.path.dirname(os.path.join(d, path)), exist_ok=True)
                pathlib.Path(d, path).write_bytes(text.encode())
            g = ["git", "-C", d, "-c", "core.autocrlf=false", "-c", "core.safecrlf=false", "-c", "user.name=lint",
                 "-c", "user.email=lint@localhost", "-c", "commit.gpgsign=false"]
            for cmd in (["init", "-q"], ["add", "-A"], ["commit", "-q", "--no-verify", "-m", "fixture"]):
                subprocess.run(g + cmd, check=True, capture_output=True)
            sha = subprocess.run(g + ["rev-parse", "HEAD"], check=True, capture_output=True).stdout.decode().strip()
            return lint(read_git(d, sha))
    for name, text, want, needle in regress:
        tree = dict(good)
        tree[new] = text
        for how, got in (("in memory", lint(tree)), ("via git", git_lint(tree))):
            mine = [b for b in got if new in b]
            ok = (not got) == want and (needle is None or any(needle in b for b in mine))
            fails += not ok
            print(("ok   " if ok else "FAIL ") + "%s (%s)" % (name, how) + ("" if ok else ": " + "; ".join(got)))
    # the directory reader feeds the same rules: the good tree written out passes, a bindings dir stays out of scope
    with tempfile.TemporaryDirectory() as d:
        for p, text in good.items():
            os.makedirs(os.path.dirname(os.path.join(d, p)), exist_ok=True)
            pathlib.Path(d, p).write_text(text)
        got = read_dir(d)
        ok = not lint(got) and "src/lte/bindings/modulegen.cc" not in got and len(got) == len(good) - 1
        fails += not ok
        print(("ok   " if ok else "FAIL ") + "the good tree read from a directory")
    print("ns3-source-lint self-test: " + ("ok" if not fails else "%d failure(s)" % fails))
    return 1 if fails else 0


def main(argv):
    if argv == ["--self-test"]:
        return self_test()
    try:
        if len(argv) == 3 and argv[0] == "--git":
            files, where = read_git(argv[1], argv[2]), "%s@%s" % (argv[1], argv[2][:8])
        elif len(argv) == 2 and argv[0] == "--dir":
            files, where = read_dir(argv[1]), argv[1]
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as exc:
        print("cannot read the ns-3 tree: %s" % (getattr(exc, "stderr", b"") or str(exc).encode()).decode().strip())
        return 2
    bad = lint(files)
    for b in bad:
        print("%s: %s" % (where, b))
    print("ns-3 source lint on %s: %d files, %s" % (where, len(files), "ok" if not bad else "%d problem(s)" % len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
