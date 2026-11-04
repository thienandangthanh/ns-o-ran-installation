/*
 * selftest-records-mutate.c: input generator for selftest-records.sh.
 *
 * Reads kpimon-decode-harness input lines "<id> <hdr_hex> <msg_hex>" on stdin. For every E2SM-KPM Format 2
 * indication message with at least two measCondUEidList items, it changes ONE field of the LAST UE ID of the
 * LAST condition item, re-encodes the message with kpimon's own asn1c types (aligned PER) and prints
 * "<id>-<mode> <hdr_hex> <msg_hex>". Every other item is left as decoded, so a judge that reads only the first
 * condition item cannot see the change; the --records "ueIdsUniform" flag must turn false.
 *
 * Modes (argv[1]):
 *   x2ap      flip bit 0 of the MeNB UE X2AP ID (en-gNB-UEID and eNB-UEID)
 *   macro     flip one bit of the en-gNB-UEID Global eNB macro eNB ID
 *   optional  add the optional gNB-CU-UE-F1AP-ID to an en-gNB-UEID
 *   mme       flip bit 0 of the eNB-UEID MME UE S1AP ID
 * A message whose last UE ID has no field for the mode is skipped (not printed).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <E2SM-KPM-IndicationMessage.h>
#include <E2SM-KPM-IndicationMessage-Format2.h>
#include <MeasurementCondUEidItem.h>
#include <MatchingUEidList.h>
#include <MatchingUEidItem.h>
#include <UEID.h>
#include <UEID-EN-GNB.h>
#include <UEID-ENB.h>
#include <GlobalENB-ID.h>

static long unhex(const char *s, unsigned char *o) {
	long n = 0;
	for (; s[0] && s[1]; s += 2) {
		unsigned v;
		if (sscanf(s, "%2x", &v) != 1) return -1;
		o[n++] = (unsigned char)v;
	}
	return n;
}

static void hex(const unsigned char *b, size_t n) {
	for (size_t i = 0; i < n; i++) printf("%02x", b[i]);
}

/* Applies the mode to one UE ID; returns 0 when the UE ID has no such field. */
static int mutate(const char *mode, UEID_t *u) {
	int en = u->present == UEID_PR_en_gNB_UEID, enb = u->present == UEID_PR_eNB_UEID;
	if (!strcmp(mode, "x2ap")) {
		if (en) u->choice.en_gNB_UEID->m_eNB_UE_X2AP_ID ^= 1;
		else if (enb && u->choice.eNB_UEID->m_eNB_UE_X2AP_ID) *u->choice.eNB_UEID->m_eNB_UE_X2AP_ID ^= 1;
		else return 0;
	} else if (!strcmp(mode, "macro")) {
		GlobalENB_ID_t *g = en ? &u->choice.en_gNB_UEID->globalENB_ID : NULL;
		if (!g || g->eNB_ID.present != ENB_ID_PR_macro_eNB_ID || g->eNB_ID.choice.macro_eNB_ID.size < 3) return 0;
		g->eNB_ID.choice.macro_eNB_ID.buf[2] ^= 0x20; /* a used bit of the 20-bit macro eNB ID */
	} else if (!strcmp(mode, "optional")) {
		if (!en || u->choice.en_gNB_UEID->gNB_CU_UE_F1AP_ID) return 0;
		u->choice.en_gNB_UEID->gNB_CU_UE_F1AP_ID = calloc(1, sizeof(*u->choice.en_gNB_UEID->gNB_CU_UE_F1AP_ID));
		if (!u->choice.en_gNB_UEID->gNB_CU_UE_F1AP_ID) return 0;
		*u->choice.en_gNB_UEID->gNB_CU_UE_F1AP_ID = 7;
	} else if (!strcmp(mode, "mme")) {
		if (!enb) return 0;
		u->choice.eNB_UEID->mME_UE_S1AP_ID ^= 1;
	} else {
		return 0;
	}
	return 1;
}

int main(int argc, char **argv) {
	if (argc != 2) {
		fprintf(stderr, "usage: %s x2ap|macro|optional|mme < lines\n", argv[0]);
		return 2;
	}
	const char *mode = argv[1];
	static char line[1 << 20], id[64], h[1 << 16], m[1 << 19];
	static unsigned char buf[1 << 19], out[1 << 19];
	while (fgets(line, sizeof line, stdin)) {
		if (sscanf(line, "%63s %65535s %524287s", id, h, m) != 3) continue;
		long n = unhex(m, buf);
		if (n <= 0) continue;
		E2SM_KPM_IndicationMessage_t *msg = NULL;
		asn_dec_rval_t r = asn_decode(0, ATS_ALIGNED_BASIC_PER, &asn_DEF_E2SM_KPM_IndicationMessage, (void **)&msg, buf,
		                              (size_t)n);
		if (r.code != RC_OK || msg->indicationMessage_formats.present !=
		                           E2SM_KPM_IndicationMessage__indicationMessage_formats_PR_indicationMessage_Format2)
			goto next;
		E2SM_KPM_IndicationMessage_Format2_t *f2 = msg->indicationMessage_formats.choice.indicationMessage_Format2;
		int items = f2->measCondUEidList.list.count;
		if (items < 2) goto next;
		MatchingUEidList_t *l = f2->measCondUEidList.list.array[items - 1]->matchingUEidList;
		if (!l || l->list.count < 1 || !mutate(mode, &l->list.array[l->list.count - 1]->ueID)) goto next;
		asn_enc_rval_t e = asn_encode_to_buffer(0, ATS_ALIGNED_BASIC_PER, &asn_DEF_E2SM_KPM_IndicationMessage, msg, out,
		                                        sizeof out);
		if (e.encoded < 0) {
			fprintf(stderr, "%s: re-encode failed\n", id);
			return 1;
		}
		printf("%s-%s %s ", id, mode, h);
		hex(out, (size_t)e.encoded);
		putchar('\n');
	next:
		ASN_STRUCT_FREE(asn_DEF_E2SM_KPM_IndicationMessage, msg);
	}
	return 0;
}
