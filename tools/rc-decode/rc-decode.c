/*
 * rc-decode: decode E2SM-RC v2.0 octets (APER) and print them as XER, one JSON
 * line per input. The gates use it to judge RC control traffic on the wire,
 * independently of the agents' codec.
 *
 *   rc-decode            stdin lines "<id> <type> <hex>", type = header |
 *                        message | outcome; prints
 *                        {"id","type","ok","len","consumed","xer"}.
 *                        ok = decode RC_OK and every octet consumed.
 *   rc-decode --selftest-outcome
 *                        encodes an E2SM-RC-ControlOutcome Format 1 with an
 *                        empty ranP-List, decodes it back and prints the hex,
 *                        the XER and whether the round trip is exact.
 *
 * Never calls asn_check_constraints: it loops forever on RANParameter-bearing
 * RC PDUs with this asn1c (extensible RANParameter-ValueType recursion).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "E2SM-RC-ControlHeader.h"
#include "E2SM-RC-ControlMessage.h"
#include "E2SM-RC-ControlOutcome.h"
#include "E2SM-RC-ControlOutcome-Format1.h"

struct buf { char *p; size_t n, cap; };

static int buf_cb(const void *data, size_t size, void *app)
{
    struct buf *b = app;
    if (b->n + size + 1 > b->cap) {
        b->cap = (b->n + size + 1) * 2;
        b->p = realloc(b->p, b->cap);
    }
    memcpy(b->p + b->n, data, size);
    b->n += size;
    b->p[b->n] = 0;
    return 0;
}

static void json_str(const char *s)
{
    putchar('"');
    for (; *s; s++) {
        if (*s == '"' || *s == '\\') { putchar('\\'); putchar(*s); }
        else if (*s == '\n') fputs("\\n", stdout);
        else if (*s == '\t') fputs("\\t", stdout);
        else if ((unsigned char)*s < 0x20) printf("\\u%04x", *s);
        else putchar(*s);
    }
    putchar('"');
}

static size_t hex2bin(const char *hex, unsigned char *out, size_t max)
{
    size_t n = 0;
    while (hex[0] && hex[1] && n < max) {
        unsigned v;
        if (sscanf(hex, "%2x", &v) != 1) break;
        out[n++] = (unsigned char)v;
        hex += 2;
    }
    return n;
}

static asn_TYPE_descriptor_t *type_of(const char *t)
{
    if (!strcmp(t, "header")) return &asn_DEF_E2SM_RC_ControlHeader;
    if (!strcmp(t, "message")) return &asn_DEF_E2SM_RC_ControlMessage;
    if (!strcmp(t, "outcome")) return &asn_DEF_E2SM_RC_ControlOutcome;
    return NULL;
}

/* Decode one value; returns 1 when RC_OK and all octets were consumed. */
static int decode_one(asn_TYPE_descriptor_t *td, const unsigned char *bin, size_t len,
                      size_t *consumed, struct buf *xer)
{
    void *p = NULL;
    asn_dec_rval_t r = aper_decode_complete(NULL, td, &p, bin, len);
    *consumed = r.consumed;
    int ok = r.code == RC_OK && r.consumed == len;
    if (r.code == RC_OK)
        xer_encode(td, p, XER_F_BASIC, buf_cb, xer);
    ASN_STRUCT_FREE(*td, p);
    return ok;
}

static int selftest_outcome(void)
{
    E2SM_RC_ControlOutcome_t *o = calloc(1, sizeof(*o));
    o->ric_controlOutcome_formats.present =
        E2SM_RC_ControlOutcome__ric_controlOutcome_formats_PR_controlOutcome_Format1;
    o->ric_controlOutcome_formats.choice.controlOutcome_Format1 =
        calloc(1, sizeof(*o->ric_controlOutcome_formats.choice.controlOutcome_Format1));
    unsigned char enc[256];
    asn_enc_rval_t er = aper_encode_to_buffer(&asn_DEF_E2SM_RC_ControlOutcome, NULL, o, enc, sizeof(enc));
    if (er.encoded < 0) { printf("{\"ok\":false,\"error\":\"encode\"}\n"); return 1; }
    size_t len = (er.encoded + 7) / 8;
    struct buf x1 = {0}, x2 = {0};
    xer_encode(&asn_DEF_E2SM_RC_ControlOutcome, o, XER_F_BASIC, buf_cb, &x1);
    size_t consumed;
    int ok = decode_one(&asn_DEF_E2SM_RC_ControlOutcome, enc, len, &consumed, &x2);
    ok = ok && x1.p && x2.p && !strcmp(x1.p, x2.p);
    printf("{\"ok\":%s,\"hex\":\"", ok ? "true" : "false");
    for (size_t i = 0; i < len; i++) printf("%02x", enc[i]);
    printf("\",\"xer\":");
    json_str(x2.p ? x2.p : "");
    printf("}\n");
    ASN_STRUCT_FREE(asn_DEF_E2SM_RC_ControlOutcome, o);
    return ok ? 0 : 1;
}

int main(int argc, char **argv)
{
    if (argc > 1 && !strcmp(argv[1], "--selftest-outcome")) return selftest_outcome();
    char line[65536], id[256], type[32], hex[65000];
    unsigned char bin[32768];
    int bad = 0;
    while (fgets(line, sizeof(line), stdin)) {
        if (sscanf(line, "%255s %31s %64999s", id, type, hex) != 3) continue;
        asn_TYPE_descriptor_t *td = type_of(type);
        if (!td) { fprintf(stderr, "unknown type %s\n", type); bad = 1; continue; }
        size_t len = hex2bin(hex, bin, sizeof(bin)), consumed = 0;
        struct buf xer = {0};
        int ok = decode_one(td, bin, len, &consumed, &xer);
        bad |= !ok;
        printf("{\"id\":");
        json_str(id);
        printf(",\"type\":\"%s\",\"ok\":%s,\"len\":%zu,\"consumed\":%zu,\"xer\":", type,
               ok ? "true" : "false", len, consumed);
        json_str(xer.p ? xer.p : "");
        printf("}\n");
        free(xer.p);
    }
    return bad;
}
