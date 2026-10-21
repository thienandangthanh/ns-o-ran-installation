/*
 * kpimon-decode-harness: decode E2SM-KPM RIC Indication header/message octets
 * with kpimon-go's OWN decoder library (libe2smwrapper.so) and report the
 * asn1c return codes. Calls asn_decode exactly as kpimon's wrapper.c does
 * (e2sm_decode_ric_indication_header / _message):
 *   asn_decode(0, ATS_ALIGNED_BASIC_PER, &asn_DEF_E2SM_KPM_Indication{Header,Message}, ...)
 *
 * stdin : one "<id> <header_hex> <message_hex>" per line ('-' = empty octets;
 *         ':' and other non-hex separators inside hex are ignored).
 * stdout: one JSON object per line (see print_result).
 * flags : --xer N          XER-print (stderr) the first N decoded headers and
 *                          the first N decoded messages (RC_OK only)
 *         --timestamp-size print TimeStamp SIZE lower bound compiled into the
 *                          linked library (4 or 8) and exit
 *         --records        add the decoded header fields and record values
 *                          (REAL as IEEE-754 bits; kpimon-decode-harness-records.c)
 *         --ranfunc        different input: "<id> <ranFunctionDefinition_hex>"
 *                          lines; decode as kpimon does (buildRanCellUeKpi) and
 *                          strictly (kpimon-decode-harness-ranfunc.c)
 *
 * msg_format is the asn1c "present" index of indicationMessage_formats
 * (1 = Format1, 2 = Format2). ts_len is reported only when the header is RC_OK.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <E2SM-KPM-IndicationHeader.h>
#include <E2SM-KPM-IndicationHeader-Format1.h>
#include <E2SM-KPM-IndicationMessage.h>
#include <per_support.h>
#include "kpimon-decode-harness.h"

/* Not declared in any generated header; non-static in TimeStamp.c. */
extern asn_per_constraints_t asn_PER_type_TimeStamp_constr_1;

static const char *code_name(int c) {
	switch (c) {
	case RC_OK: return "RC_OK";
	case RC_WMORE: return "RC_WMORE";
	case RC_FAIL: return "RC_FAIL";
	}
	return "RC_UNKNOWN";
}

/* Hex (with optional separators) -> bytes. Returns length, or -1 on bad hex. */
long hex_decode(const char *s, unsigned char *out) {
	long n = 0;
	int hi = -1;
	if (strcmp(s, "-") == 0) return 0;
	for (; *s; s++) {
		int v;
		if (*s == ':' || *s == ' ') continue;
		if (*s >= '0' && *s <= '9') v = *s - '0';
		else if (*s >= 'a' && *s <= 'f') v = *s - 'a' + 10;
		else if (*s >= 'A' && *s <= 'F') v = *s - 'A' + 10;
		else return -1;
		if (hi < 0) hi = v; else { out[n++] = (unsigned char)(hi << 4 | v); hi = -1; }
	}
	return hi < 0 ? n : -1;
}

void json_octets(const unsigned char *b, size_t n) {
	putchar('"');
	for (size_t i = 0; i < n; i++) {
		if (b[i] == '"' || b[i] == '\\') { putchar('\\'); putchar(b[i]); }
		else if (b[i] < 0x20 || b[i] >= 0x7f) printf("\\u%04x", b[i]);
		else putchar(b[i]);
	}
	putchar('"');
}

void json_str(const char *s) { json_octets((const unsigned char *)s, strlen(s)); }

int main(int argc, char **argv) {
	long xer_left_h = 0, xer_left_m = 0;
	int records = 0;
	char *line = NULL;
	size_t cap = 0;
	ssize_t got;

	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--timestamp-size") == 0) {
			printf("%ld\n", (long)asn_PER_type_TimeStamp_constr_1.size.lower_bound);
			return 0;
		} else if (strcmp(argv[i], "--ranfunc") == 0) {
			return run_ranfunc_mode();
		} else if (strcmp(argv[i], "--records") == 0) {
			records = 1;
		} else if (strcmp(argv[i], "--xer") == 0 && i + 1 < argc) {
			xer_left_h = xer_left_m = atol(argv[++i]);
		} else {
			fprintf(stderr, "usage: %s [--xer N] [--records] [--timestamp-size] [--ranfunc] < lines\n", argv[0]);
			return 2;
		}
	}

	while ((got = getline(&line, &cap, stdin)) > 0) {
		char *id, *h, *m, *save = NULL;
		unsigned char *hb, *mb;
		long hl, ml;
		const char *hcode, *mcode;
		long hcons = 0, mcons = 0, ts_len = -1, msg_format = -1;
		E2SM_KPM_IndicationHeader_t *hdr = NULL;
		E2SM_KPM_IndicationMessage_t *msg = NULL;
		asn_dec_rval_t r;

		id = strtok_r(line, " \t\r\n", &save);
		if (!id || id[0] == '#') continue;
		h = strtok_r(NULL, " \t\r\n", &save);
		m = strtok_r(NULL, " \t\r\n", &save);
		if (!h || !m) { fprintf(stderr, "skip malformed line (id=%s)\n", id); continue; }

		hb = malloc(strlen(h) / 2 + 2);
		mb = malloc(strlen(m) / 2 + 2);
		hl = hex_decode(h, hb);
		ml = hex_decode(m, mb);

		if (hl < 0) hcode = "BAD_HEX";
		else {
			r = asn_decode(0, ATS_ALIGNED_BASIC_PER, &asn_DEF_E2SM_KPM_IndicationHeader,
			               (void **)&hdr, hb, (size_t)hl);
			hcode = code_name(r.code);
			hcons = (long)r.consumed;
			if (r.code == RC_OK && hdr) {
				if (hdr->indicationHeader_formats.present ==
				    E2SM_KPM_IndicationHeader__indicationHeader_formats_PR_indicationHeader_Format1)
					ts_len = (long)hdr->indicationHeader_formats.choice
					             .indicationHeader_Format1->colletStartTime.size;
				if (xer_left_h > 0) {
					xer_left_h--;
					fprintf(stderr, "--- header %s ---\n", id);
					xer_fprint(stderr, &asn_DEF_E2SM_KPM_IndicationHeader, hdr);
				}
			}
		}
		if (ml < 0) mcode = "BAD_HEX";
		else {
			r = asn_decode(0, ATS_ALIGNED_BASIC_PER, &asn_DEF_E2SM_KPM_IndicationMessage,
			               (void **)&msg, mb, (size_t)ml);
			mcode = code_name(r.code);
			mcons = (long)r.consumed;
			if (r.code == RC_OK && msg) {
				msg_format = (long)msg->indicationMessage_formats.present;
				if (xer_left_m > 0) {
					xer_left_m--;
					fprintf(stderr, "--- message %s ---\n", id);
					xer_fprint(stderr, &asn_DEF_E2SM_KPM_IndicationMessage, msg);
				}
			}
		}

		printf("{\"id\":"); json_str(id);
		printf(",\"hdr_code\":\"%s\",\"hdr_consumed\":%ld,\"hdr_len\":%ld", hcode, hcons, hl < 0 ? 0 : hl);
		printf(",\"msg_code\":\"%s\",\"msg_consumed\":%ld,\"msg_len\":%ld", mcode, mcons, ml < 0 ? 0 : ml);
		if (ts_len >= 0) printf(",\"ts_len\":%ld", ts_len); else printf(",\"ts_len\":null");
		if (msg_format >= 0) printf(",\"msg_format\":%ld", msg_format); else printf(",\"msg_format\":null");
		if (records && hdr && strcmp(hcode, "RC_OK") == 0) print_header_fields(hdr);
		if (records && msg && strcmp(mcode, "RC_OK") == 0) print_message_records(msg);
		printf("}\n");

		ASN_STRUCT_FREE(asn_DEF_E2SM_KPM_IndicationHeader, hdr);
		ASN_STRUCT_FREE(asn_DEF_E2SM_KPM_IndicationMessage, msg);
		free(hb);
		free(mb);
	}
	free(line);
	return 0;
}
