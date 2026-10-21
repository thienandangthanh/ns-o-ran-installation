/*
 * Shared helpers of kpimon-decode-harness (kpimon-decode-harness.c,
 * kpimon-decode-harness-ranfunc.c, kpimon-decode-harness-records.c).
 */
#ifndef KPIMON_DECODE_HARNESS_H
#define KPIMON_DECODE_HARNESS_H

#include <E2SM-KPM-IndicationHeader.h>
#include <E2SM-KPM-IndicationMessage.h>

/* Hex (':' and ' ' ignored) -> bytes; returns length or -1 on bad hex. */
long hex_decode(const char *s, unsigned char *out);

/* JSON string literal of a C string / of n raw octets (non-printables escaped). */
void json_str(const char *s);
void json_octets(const unsigned char *b, size_t n);

/* --ranfunc mode: stdin "<id> <hex>" lines -> one JSON object per line. */
int run_ranfunc_mode(void);

/* --records: ',"records":[...]' (+ format-2 UE-ID summary) for a decoded message,
 * ',"header":{...}' for a decoded header. REAL values are printed as their
 * IEEE-754 bit pattern so callers can compare bit-exactly. */
void print_message_records(const E2SM_KPM_IndicationMessage_t *msg);
void print_header_fields(const E2SM_KPM_IndicationHeader_t *hdr);

#endif
