/*
 * --records output of kpimon-decode-harness: the decoded KPM record values of
 * an indication message (as kpimon reads them: Format1 measData items in
 * order, Format2 measData[0] records metric-major, plus every Format2 item's
 * records as itemRecords, its UE IDs as ueIds and kpimon's ueId tags as
 * ueIdTags) and the decoded header fields. REAL records are printed as the 16-hex-digit IEEE-754 bit pattern of
 * the double kpimon would read, so a caller can compare bit-exactly.
 */
#include <inttypes.h>
#include <stdio.h>
#include <string.h>
#include <E2SM-KPM-IndicationHeader-Format1.h>
#include <E2SM-KPM-IndicationMessage-Format1.h>
#include <E2SM-KPM-IndicationMessage-Format2.h>
#include <MeasurementDataItem.h>
#include <MeasurementRecordItem.h>
#include <MeasurementCondUEidItem.h>
#include <MatchingUEidList.h>
#include <MatchingUEidItem.h>
#include <UEID.h>
#include <UEID-GNB.h>
#include <UEID-EN-GNB.h>
#include <UEID-ENB.h>
#include <GlobalENB-ID.h>
#include <wrapper.h>
#include "kpimon-decode-harness.h"

static void print_record_list(const MeasurementRecord_t *rec) {
	for (int i = 0; i < rec->list.count; i++) {
		const MeasurementRecordItem_t *r = rec->list.array[i];
		if (i) putchar(',');
		if (r->present == MeasurementRecordItem_PR_integer) {
			printf("{\"t\":\"int\",\"v\":%lu}", (unsigned long)r->choice.integer);
		} else if (r->present == MeasurementRecordItem_PR_real) {
			uint64_t bits;
			memcpy(&bits, &r->choice.real, 8);
			printf("{\"t\":\"real\",\"bits\":\"%016" PRIx64 "\"}", bits);
		} else if (r->present == MeasurementRecordItem_PR_noValue) {
			printf("{\"t\":\"none\"}");
		} else {
			printf("{\"t\":\"other%d\"}", (int)r->present);
		}
	}
}

/* Hex of an OCTET STRING's octets, uppercase (PLMN identity, MME group ID, MME code). */
static void print_octets_hex(const OCTET_STRING_t *o) {
	putchar('"');
	for (size_t i = 0; o && o->buf && i < o->size; i++) printf("%02X", o->buf[i]);
	putchar('"');
}

/* GlobalENB-ID as {"plmn", "macroEnbId" (%05X of the 20-bit macro eNB ID)}, or {"plmn", "eNBIdChoice"} for any other
 * eNB ID (a check then fails on it). */
static void print_global_enb(const GlobalENB_ID_t *g) {
	printf("{\"plmn\":");
	print_octets_hex(&g->pLMNIdentity);
	const BIT_STRING_t *m = &g->eNB_ID.choice.macro_eNB_ID;
	if (g->eNB_ID.present == ENB_ID_PR_macro_eNB_ID && m->buf && m->size == 3 && m->bits_unused == 4)
		printf(",\"macroEnbId\":\"%05lX\"}", ((unsigned long)m->buf[0] << 12) | ((unsigned long)m->buf[1] << 4) |
		                                     ((unsigned long)m->buf[2] >> 4));
	else
		printf(",\"eNBIdChoice\":%d}", (int)g->eNB_ID.present);
}

static const char *ueid_choice_name(UEID_PR p) {
	static const char *names[] = {"none", "gNB-UEID", "gNB-DU-UEID", "gNB-CU-UP-UEID", "ng-eNB-UEID",
	                              "ng-eNB-DU-UEID", "en-gNB-UEID", "eNB-UEID"};
	return (p >= 0 && (size_t)p < sizeof(names) / sizeof(names[0])) ? names[p] : "unknown";
}

/* One UE ID in the representation of the RC UE ID transform: en-gNB-UEID {mEnbUeX2apId, globalEnbId} (+ "optional":
 * true when any optional member is present), eNB-UEID {mmeUeS1apId, gummei, mEnbUeX2apId when present}
 * (+ "globalEnbPresent": true), gNB-UEID {amfUeNgapId}; any other CHOICE only its name. */
static void print_ue_id(const UEID_t *id) {
	printf("{\"type\":\"%s\"", ueid_choice_name(id->present));
	if (id->present == UEID_PR_en_gNB_UEID && id->choice.en_gNB_UEID) {
		const UEID_EN_GNB_t *e = id->choice.en_gNB_UEID;
		printf(",\"mEnbUeX2apId\":%ld,\"globalEnbId\":", (long)e->m_eNB_UE_X2AP_ID);
		print_global_enb(&e->globalENB_ID);
		if (e->m_eNB_UE_X2AP_ID_Extension || e->gNB_CU_UE_F1AP_ID || e->gNB_CU_CP_UE_E1AP_ID_List || e->ran_UEID)
			printf(",\"optional\":true");
	} else if (id->present == UEID_PR_eNB_UEID && id->choice.eNB_UEID) {
		const UEID_ENB_t *e = id->choice.eNB_UEID;
		printf(",\"mmeUeS1apId\":%lu,\"gummei\":{\"plmn\":", (unsigned long)e->mME_UE_S1AP_ID);
		print_octets_hex(&e->gUMMEI.pLMN_Identity);
		printf(",\"mmeGroupId\":");
		print_octets_hex(&e->gUMMEI.mME_Group_ID);
		printf(",\"mmeCode\":");
		print_octets_hex(&e->gUMMEI.mME_Code);
		printf("}");
		if (e->m_eNB_UE_X2AP_ID) printf(",\"mEnbUeX2apId\":%ld", (long)*e->m_eNB_UE_X2AP_ID);
		if (e->globalENB_ID) printf(",\"globalEnbPresent\":true");
	} else if (id->present == UEID_PR_gNB_UEID && id->choice.gNB_UEID) {
		uintmax_t v = 0;
		if (asn_INTEGER2umax(&id->choice.gNB_UEID->amf_UE_NGAP_ID, &v) == 0) printf(",\"amfUeNgapId\":%ju", v);
	}
	putchar('}');
}

/* The UE IDs of the first measCondUEidList item ("ueIds"), kpimon's own ueId tag per UE position
 * ("ueIdTags": e2sm_kpm_format2_ue_id_tag, the reason string where it returns -1), and whether every item
 * carries the same number of UE IDs. */
static void print_ue_ids(const E2SM_KPM_IndicationMessage_Format2_t *f2) {
	const MeasurementCondUEidList_t *l = &f2->measCondUEidList;
	int n0 = -1, same = 1;
	for (int i = 0; i < l->list.count; i++) {
		const MeasurementCondUEidItem_t *c = l->list.array[i];
		int n = c->matchingUEidList ? c->matchingUEidList->list.count : 0;
		if (n0 < 0) n0 = n; else if (n != n0) same = 0;
	}
	printf(",\"condItems\":%d,\"ueIdsPerItem\":%d,\"ueIdsUniform\":%s,\"ueIds\":[", l->list.count, n0,
	       same ? "true" : "false");
	const MatchingUEidList_t *u = l->list.count > 0 ? l->list.array[0]->matchingUEidList : NULL;
	for (int k = 0; u && k < u->list.count; k++) {
		if (k) putchar(',');
		print_ue_id(&u->list.array[k]->ueID);
	}
	printf("],\"ueIdTags\":[");
	for (int k = 0; u && k < u->list.count; k++) {
		char tag[256];
		tag[0] = '\0';
		(void)e2sm_kpm_format2_ue_id_tag(f2, (size_t)k, tag, sizeof(tag));  /* the tag, or the reason on -1 */
		if (k) putchar(',');
		json_str(tag);
	}
	printf("]");
}

void print_message_records(const E2SM_KPM_IndicationMessage_t *msg) {
	const struct E2SM_KPM_IndicationMessage__indicationMessage_formats *f = &msg->indicationMessage_formats;
	if (f->present == E2SM_KPM_IndicationMessage__indicationMessage_formats_PR_indicationMessage_Format1) {
		const E2SM_KPM_IndicationMessage_Format1_t *f1 = f->choice.indicationMessage_Format1;
		printf(",\"measDataItems\":%d,\"records\":[", f1->measData.list.count);
		for (int i = 0; i < f1->measData.list.count; i++) {
			if (i && f1->measData.list.array[i]->measRecord.list.count) putchar(',');
			print_record_list(&f1->measData.list.array[i]->measRecord);
		}
		printf("]");
		if (f1->granulPeriod) printf(",\"granulPeriod\":%lu", (unsigned long)*f1->granulPeriod);
	} else if (f->present == E2SM_KPM_IndicationMessage__indicationMessage_formats_PR_indicationMessage_Format2) {
		const E2SM_KPM_IndicationMessage_Format2_t *f2 = f->choice.indicationMessage_Format2;
		printf(",\"measDataItems\":%d,\"records\":[", f2->measData.list.count);
		if (f2->measData.list.count > 0) print_record_list(&f2->measData.list.array[0]->measRecord);
		/* Every item's records too: a UE absent from a granularity interval is
		 * noValue there, so item 0 alone may carry no node or seq. */
		printf("],\"itemRecords\":[");
		for (int i = 0; i < f2->measData.list.count; i++) {
			printf("%s[", i ? "," : "");
			print_record_list(&f2->measData.list.array[i]->measRecord);
			printf("]");
		}
		printf("]");
		if (f2->granulPeriod) printf(",\"granulPeriod\":%lu", (unsigned long)*f2->granulPeriod);
		print_ue_ids(f2);
	}
}

void print_header_fields(const E2SM_KPM_IndicationHeader_t *hdr) {
	if (hdr->indicationHeader_formats.present !=
	    E2SM_KPM_IndicationHeader__indicationHeader_formats_PR_indicationHeader_Format1)
		return;
	const E2SM_KPM_IndicationHeader_Format1_t *h = hdr->indicationHeader_formats.choice.indicationHeader_Format1;
	printf(",\"header\":{\"ts_hex\":\"");
	for (size_t i = 0; i < h->colletStartTime.size; i++) printf("%02x", h->colletStartTime.buf[i]);
	printf("\"");
	if (h->senderName) { printf(",\"senderName\":"); json_octets(h->senderName->buf, h->senderName->size); }
	if (h->senderType) { printf(",\"senderType\":"); json_octets(h->senderType->buf, h->senderType->size); }
	if (h->vendorName) { printf(",\"vendorName\":"); json_octets(h->vendorName->buf, h->vendorName->size); }
	printf("}");
}
